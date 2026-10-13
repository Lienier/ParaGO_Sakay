const Driver = require('../models/driver');
const User = require('../models/user');
const Jeepney = require('../models/jeepney');
const Route = require('../models/route');
const Trip = require('../models/tripSession');
const Activity = require('../models/activityLog');
const queue = require('./terminalQueue.service');
const { evaluateArrival } = require('../utils/destinationArrival');
const { haversineMeters } = require('../utils/geo');
const { resolveRouteTerminalStop } = require('./hybridDispatch.service');
const { isRoutePickupNearRoad } = require('../utils/routeGeo');
const { assertVehicleAllowed } = require('./operatingRules.service');

function departureCheck(observation, previous, terminal, radius, route, now) {
  const o = observation, captured = new Date(o.capturedAt).getTime();
  const reset = reason => ({ reason, reached: false, state: { observations: 0 } });
  if (!o.streamId || !Number.isSafeInteger(o.sequence) || o.sequence < 1) return reset('unordered');
  if (!Number.isFinite(captured) || captured > +now || +now - captured > 15000) return reset('stale');
  if (!Number.isFinite(o.accuracyMeters) || o.accuracyMeters < 0 || o.accuracyMeters > 30) return reset('accuracy');
  if (!Number.isFinite(o.speedMetersPerSecond) || o.speedMetersPerSecond < 5 / 3.6) return reset('not_moving');
  const [lng, lat] = terminal?.coordinates || [];
  if (![lng, lat, o.longitude, o.latitude].every(Number.isFinite)) return reset('coordinates');
  if (haversineMeters(lat, lng, o.latitude, o.longitude) <= radius + 50) return reset('inside_terminal');
  if (!isRoutePickupNearRoad({ route, longitude: o.longitude, latitude: o.latitude, maxDistanceMeters: 100 })) return reset('off_route');
  if (previous.streamId === o.streamId && (o.sequence <= previous.sequence || captured <= +new Date(previous.lastCapturedAt))) {
    return { reason: 'repeated', reached: false, state: previous };
  }
  const continues = previous.observations > 0 && previous.streamId === o.streamId && captured > +new Date(previous.lastCapturedAt) && captured - +new Date(previous.lastCapturedAt) <= 15000;
  const state = { streamId: o.streamId, sequence: o.sequence, lastCapturedAt: new Date(captured),
    startedAt: continues ? previous.startedAt : new Date(captured), observations: continues ? previous.observations + 1 : 1 };
  return { reason: 'valid', state, reached: state.observations >= 3 && captured - +new Date(state.startedAt) >= 10000 };
}

async function log(session, trip, driver, action, details) {
  await Activity.create([{ actorId: driver.userId, actorRole: 'system', action, entity: 'TripSession',
    entityId: String(trip?._id || driver._id), details }], { session });
}

async function runAutomaticDriverLifecycle({ actor, jeepneyId, observation, now = new Date(), phase = 'progress' }) {
  const config = require('../config/env');
  if (!config.automaticGroupFlowEnabled || !config.automaticDriverLifecycleEnabled || !observation) return null;
  const assigned = await Driver.findOne({ userId: actor._id, status: 'active', assignedJeepneyId: jeepneyId, automaticJourneyPaused: { $ne: true } });
  if (!assigned?.assignedRouteId) return null;
  const result = await queue.transaction(assigned.assignedRouteId, async session => {
    // The route, driver and trip writes serialize GPS transitions with queue,
    // booking and occupancy transactions. No transition runs on rejected GPS.
    const driver = await Driver.findOneAndUpdate({ _id: assigned._id, status: 'active', assignedJeepneyId: jeepneyId, assignedRouteId: assigned.assignedRouteId, automaticJourneyPaused: { $ne: true } },
      { $set: { updatedAt: now } }, { new: true, session });
    if (!driver || !await User.exists({ _id: driver.userId, status: 'active' }).session(session)) return null;
    const vehicle = await Jeepney.findById(jeepneyId).session(session);
    const route = await Route.findOne({ _id: driver.assignedRouteId, status: 'active' }).session(session);
    if (!route || vehicle?.status !== 'active' || !(vehicle.capacity > 0) ||
        (vehicle.currentDriverId && String(vehicle.currentDriverId) !== String(driver._id))) return null;
    const conflicting = await Trip.findOne({ status: { $in: ['scheduled', 'active'] }, $or: [{ driverId: driver._id }, { jeepneyId }] }).session(session);
    if (conflicting && (String(conflicting.driverId) !== String(driver._id) || String(conflicting.routeId) !== String(route._id) || String(conflicting.jeepneyId) !== String(jeepneyId))) return null;
    let trip = conflicting;
    // Journeys already in progress retain their old behavior until they finish.
    if (trip && trip.flowVersion !== 2) return null;
    const terminal = resolveRouteTerminalStop(route);
    if (!terminal) return null;
    if (phase === 'finish') {
      if (!trip || trip.status !== 'active' || trip.operatingMode !== 'route') return null;
      const stops = [...(route.stops || [])].sort((a, b) => a.order - b.order);
      const end = stops.at(-1)?.location || { type: 'Point', coordinates: route.path?.coordinates?.at(-1) };
      // Prevent finishing a circular route immediately at its departure point.
      if (+now - +new Date(trip.resumedAt || trip.startedAt) < 60000) return null;
      const checked = evaluateArrival({ members: [{ destinationLocation: end }], observation, previous: trip.automaticFinishCheck || {}, now });
      trip.automaticFinishCheck = checked.state;
      await trip.save({ session });
      if (checked.reachedKey) {
        const seats = await require('./seatAccounting.service').counts(trip, session);
        if (seats.occupied === 0 && seats.reserved === 0) return { action: 'finish', tripId: String(trip._id), driverId: String(driver._id) };
      }
      if (checked.reason !== 'valid' && checked.reason !== 'repeated') await log(session, trip, driver, 'gps_trip_finish_rejected', { reason: checked.reason, sequence: observation.sequence });
      return null;
    }
    if (!trip || trip.status === 'scheduled') {
      const previous = driver.automaticJourneyCheck || {};
      if (previous.completedAt && +now - +new Date(previous.completedAt) < 120000) return null;
      const checked = evaluateArrival({ members: [{ destinationLocation: terminal.location }], observation, previous, now });
      driver.automaticJourneyCheck = checked.state;
      await driver.save({ session });
      if (!checked.reachedKey) {
        if (checked.reason !== 'valid' && checked.reason !== 'repeated') await log(session, trip, driver, 'gps_trip_start_rejected', { reason: checked.reason, sequence: observation.sequence });
        return null;
      }
      await assertVehicleAllowed(vehicle, session, now);
      const document = { flowVersion: 2, automaticLifecycle: true, driverId: driver._id, jeepneyId, routeId: route._id,
        routePathSnapshot: route.path, terminalStopRef: terminal.stopRef, terminalLocation: terminal.location, terminalRadiusMeters: terminal.radiusMeters };
      const started = await queue.checkIn({ session, existingId: trip?._id, document, actor,
        requestId: `auto-start-${driver._id}-${observation.sequence}` });
      await log(session, started, driver, 'automatic_trip_started', { streamId: observation.streamId, sequence: observation.sequence });
      return { action: 'started', tripId: String(started._id) };
    }
    if (trip.operatingMode === 'terminal_queue' && trip.terminalQueueStatus === 'loading') {
      const checked = departureCheck(observation, trip.automaticDepartureCheck || {}, terminal.location, trip.terminalRadiusMeters || terminal.radiusMeters || 75, route, now);
      trip.automaticDepartureCheck = checked.state;
      await trip.save({ session });
      if (checked.reached) return { action: 'depart', tripId: String(trip._id) };
      if (checked.reason !== 'valid' && checked.reason !== 'repeated') await log(session, trip, driver, 'gps_departure_rejected', { reason: checked.reason, sequence: observation.sequence });
    }
    return null;
  }, { publishChanges: false });
  if (result?.action === 'started') await queue.publish(assigned.assignedRouteId);
  if (result?.action === 'depart') {
    try {
      await queue.change({ tripId: result.tripId, actor, action: 'depart', requestId: `auto-depart-${result.tripId}`, reason: 'Fresh ordered GPS detected departure' });
    } catch (error) {
      if (error.statusCode !== 409 || !await Trip.exists({ _id: result.tripId, operatingMode: 'route', terminalQueueStatus: 'departed' })) throw error;
    }
  } else if (result?.action === 'finish') {
    try {
      await require('./tripLifecycle.service').endTrip(result.tripId, { actor, requestId: `auto-finish-${result.tripId}`, reason: 'Stopped at route end with no passengers or reservations', automatic: true, onlyIfEmpty: true });
      await Driver.updateOne({ _id: result.driverId }, { $set: { automaticJourneyCheck: { observations: 0, completedAt: now } } });
    } catch (error) { if (error.statusCode !== 409) throw error; }
  }
  return result;
}
async function processAutomaticDriverLifecycle(input) {
  try { return await runAutomaticDriverLifecycle(input); }
  catch (error) {
    // A queue/coding/assignment restriction blocks the transition, not the
    // already accepted GPS update. Keep location sharing working for the driver.
    if (![403, 409].includes(error.statusCode)) throw error;
    try {
      await Activity.create({ actorId: input.actor._id, actorRole: 'system', action: 'automatic_trip_transition_blocked',
        entity: 'Jeepney', entityId: String(input.jeepneyId), details: { phase: input.phase || 'progress', code: error.code, reason: error.message } });
    } catch (_) { console.error('[Automatic trip] Diagnostic record failed'); }
    return { action: 'blocked', code: error.code, reason: error.message };
  }
}
module.exports = { processAutomaticDriverLifecycle, departureCheck };
