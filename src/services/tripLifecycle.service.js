const mongoose = require('mongoose');
const Trip = require('../models/tripSession');
const Ride = require('../models/rideSession');
const Pickup = require('../models/pickupRequest');
const Alert = require('../models/stopAlert');
const Jeepney = require('../models/jeepney');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const { DRIVER_ERROR_CODES, driverError } = require('../utils/driverError');
const { invalidateDriverActiveContext } = require('./activeDriverContext.service');
const { publishNotification } = require('./notificationPublisher');
const { serializeRideSession } = require('../utils/realtimePayloads');
const INACTIVITY_MS = 5 * 60 * 1000;

async function createTripRecord(Model, document, { accepting = false, beforeCreate } = {}) {
  const terminal = document.pickupType === 'terminal' && accepting;
  const queue = require('./terminalQueue.service');
  if (terminal) await queue.prepare(document.routeId);
  const session = await mongoose.startSession();
  let record;
  try {
    await session.withTransaction(async () => {
      if (terminal) await queue.lock(document.routeId, session);
      if (accepting) {
        const journey = require('./passengerJourney.service');
        await journey.lockPassenger(document.passengerId, session);
        await journey.assertCanBook(document.passengerId, session);
      }
      const trip = await Trip.findOneAndUpdate({ _id: document.tripSessionId, status: 'active',
        ...(accepting ? { acceptRequests: true, ...(document.flowVersion === 2 ? { flowVersion: 2 } : {}) } : {}) },
      { $inc: { lifecycleRevision: 1 } }, { new: true, session });
      if (!trip) throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'This trip is closed or is no longer accepting pickup requests.', 'Refresh the trip status and choose an available trip.');
      if (accepting) {
        const vehicle = await Jeepney.findById(trip.jeepneyId).session(session);
        const driver = trip.driverId && await require('../models/driver').findById(trip.driverId).session(session);
        const route = await require('../models/route').findById(trip.routeId).session(session);
        if (vehicle?.status !== 'active' || driver?.status !== 'active' || route?.status !== 'active') {
          throw new (require('../utils/apiError'))(409, 'This driver, jeep or route is no longer available for bookings');
        }
        await require('./operatingRules.service').assertVehicleAllowed(vehicle, session);
      }
      if (terminal) await queue.reserve(trip, session, document.partySize ?? 1);
      else if (accepting) await require('./seatAccounting.service').assertCapacity(trip, document.partySize ?? 1, session);
      if (beforeCreate) await beforeCreate(session);
      [record] = await Model.create([document], { session });
    });
  } finally { await session.endSession(); }
  return record;
}

// Trip writes serialize this transaction with boarding's occupancy write.
async function endTrip(tripId, { actor, requestId, reason, automatic = false, onlyIfEmpty = false } = {}) {
  const original = await Trip.findById(tripId);
  const terminal = original?.operatingMode === 'terminal_queue';
  const queue = require('./terminalQueue.service');
  if (terminal) { queue.validateActor(actor, requestId, reason); await queue.prepare(original.routeId); }
  const session = await mongoose.startSession();
  let trip;
  let rides;
  try {
    await session.withTransaction(async () => {
      if (terminal) await queue.lock(original.routeId, session);
      const now = new Date();
      trip = await Trip.findOneAndUpdate({ _id: tripId, status: { $in: ['active', 'scheduled'] }, ...(onlyIfEmpty ? { occupancyCount: 0, manualOccupancyCount: 0 } : {}) },
        { $set: { status: 'completed', endedAt: now, active: false, acceptRequests: false,
          occupancyCount: 0, manualOccupancyCount: 0, terminalQueueStatus: 'departed' },
        $unset: { inactivityPausedAt: 1 } }, { new: true, session });
      if (!trip) throw driverError(409, DRIVER_ERROR_CODES.TRIP_ALREADY_CLOSED,
        'This trip has already ended.', 'Refresh the trip status before trying again.');
      if (onlyIfEmpty) {
        const seats = await require('./seatAccounting.service').counts(original, session);
        if (seats.occupied > 0 || seats.reserved > 0) throw driverError(409, 'TRIP_NOT_EMPTY', 'Passengers or bookings still remain.', 'Automatic completion waits for them to finish.');
      }
      await require('../models/activityLog').create([{ actorId: actor?._id, actorRole: automatic ? 'system' : actor?.role,
        action: automatic ? 'automatic_trip_completed' : 'trip_completed', entity: 'TripSession', entityId: String(tripId), details: { reason } }], { session });
      rides = await Ride.find({ tripSessionId: tripId, status: { $in: ['onboard', 'waiting'] } }).session(session);
      for (const ride of rides.filter(r => r.flowVersion === 2)) {
        const activeMembers = ride.members.filter(m => m.status === 'onboard');
        // Early closure is an actual unloading event at the jeep position, never a planned destination visit.
        const vehicle = await Jeepney.findById(trip.jeepneyId).session(session);
        const priorEvents = ride.unloadMutations.length;
        require('./memberUnloading.service').finishMembers(ride, activeMembers, { now, method: 'trip_ended', requestId: `end-${tripId}`, actorRole: 'system', actorId: 'system' });
        for (const event of ride.unloadMutations.slice(priorEvents)) { event.destinationStopRef = 'Trip ended early'; event.destinationLocation = vehicle?.lastKnownLocation?.toObject?.() || vehicle?.lastKnownLocation; }
        await ride.save({ session });
        await Pickup.updateOne({ _id: ride.pickupRequestId, flowVersion: 2 },
          { $set: { members: ride.members.map(m => m.toObject()) } }, { session });
      }
      await Ride.updateMany({ tripSessionId: tripId, flowVersion: { $ne: 2 }, status: { $in: ['onboard', 'waiting'] } },
        { $set: { status: 'completed', remainingCount: 0, endedAt: now, canSendStopAlert: false, offboardingMethod: 'trip_ended' }, $inc: { revision: 1 } }, { session });
      await Pickup.updateMany({ tripSessionId: tripId, flowVersion: 2, status: { $in: ['pending', 'acknowledged'] } },
        { $set: { status: 'cancelled', 'members.$[].status': 'cancelled' } }, { session });
      await Pickup.updateMany({ tripSessionId: tripId, flowVersion: { $ne: 2 }, status: { $in: ['pending', 'acknowledged'] } },
        { $set: { status: 'cancelled' } }, { session });
      await Alert.updateMany({ tripSessionId: tripId, status: { $in: ['sent', 'seen', 'acknowledged'] } },
        { $set: { status: 'dismissed', acknowledgedAt: now } }, { session });
      if (terminal) {
        await queue.promote(original.routeId, session);
        await queue.audit(trip, actor, 'end_trip', requestId, reason, session);
      }
    });
  } finally { await session.endSession(); }
  await invalidateDriverActiveContext(trip.driverId);
  if (terminal) await queue.publish(original.routeId);
  require('../realtime/socketServer').emitOperationsChanged({ type: 'trip.completed', routeId: String(original.routeId), role: 'driver' });
  // Notifications follow commit; delivery failure must not undo a closed trip.
  for (const ride of rides) {
    try {
      const passenger = await Passenger.findById(ride.passengerId).select('userId');
      const completed = await Ride.findById(ride._id);
      await publishNotification({ userId: passenger?.userId, type: 'ride_completed',
        title: 'Trip ended', body: 'The driver or administrator ended this trip. Your ride is now closed.',
        payload: { rideSessionId: String(ride._id), tripSessionId: String(tripId),
          completionMethod: 'trip_ended', rideSession: serializeRideSession(completed) }, category: 'ride' });
    } catch (_) { console.error('[Trip lifecycle] Completion notification failed'); }
  }
  return trip;
}

async function pauseInactiveTrips(now = new Date()) {
  await require('./terminalQueue.service').reconcile();
  const cutoff = new Date(now.getTime() - INACTIVITY_MS);
  let paused = 0;
  const candidates = Trip.find({ status: 'active', operatingMode: { $ne: 'terminal_queue' }, inactivityPausedAt: null,
    createdAt: { $lte: cutoff }, $and: [
      { $or: [{ startedAt: null }, { startedAt: { $lte: cutoff } }] },
      { $or: [{ resumedAt: null }, { resumedAt: { $lte: cutoff } }] },
    ] }).cursor();
  for await (const trip of candidates) {
    const vehicle = await Jeepney.findById(trip.jeepneyId).select('lastSeenAt');
    if (vehicle?.lastSeenAt && vehicle.lastSeenAt > cutoff) continue;
    const updated = await Trip.findOneAndUpdate({ _id: trip._id, status: 'active',
      inactivityPausedAt: null, updatedAt: trip.updatedAt },
    { $set: { acceptRequests: false, inactivityPausedAt: now } }, { new: true });
    if (updated) {
      paused++;
      await invalidateDriverActiveContext(updated.driverId);
      try {
        const driver = await Driver.findById(updated.driverId).select('userId');
        await publishNotification({ userId: driver?.userId, type: 'trip_inactivity_paused',
          title: 'Pickups paused', body: 'No driver location was received for five minutes. Reopen pickup requests to resume, or end the trip.',
          payload: { tripSessionId: String(updated._id) }, category: 'trip' });
      } catch (_) { console.error('[Trip lifecycle] Inactivity notification failed'); }
    }
  }
  return paused;
}

async function setAvailability(tripId, acceptRequests) {
  if (acceptRequests) {
    const existing = await Trip.findById(tripId);
    if (existing) await require('./operatingRules.service').assertVehicleAllowed(await Jeepney.findById(existing.jeepneyId));
  }
  const trip = await Trip.findOneAndUpdate({ _id: tripId, status: 'active', operatingMode: { $ne: 'terminal_queue' } },
    acceptRequests ? { $set: { acceptRequests: true, resumedAt: new Date() }, $unset: { inactivityPausedAt: 1 } }
      : { $set: { acceptRequests: false } }, { new: true });
  if (!trip) throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
    'Pickup availability can only change while the trip is active.', 'Refresh the trip status before trying again.');
  await invalidateDriverActiveContext(trip.driverId);
  return trip;
}

module.exports = { endTrip, pauseInactiveTrips, setAvailability, createTripRecord, INACTIVITY_MS };
