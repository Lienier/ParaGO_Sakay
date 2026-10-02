const Trip = require('../models/tripSession');
const Driver = require('../models/driver');
const { haversineMeters } = require('../utils/geo');
const terminalQueue = require('./terminalQueue.service');

const MAX_FIX_AGE_MS = 60 * 1000;
const MAX_ACCURACY_METERS = 50;
const validNumber = value => typeof value === 'number' && Number.isFinite(value);
const validCoordinates = (lat, lng) => validNumber(lat) && validNumber(lng) &&
  Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

async function processTerminalArrival({ actor, jeepneyId, latitude, longitude,
  accuracyMeters, streamId, sequence, capturedAt, now = new Date() }) {
  if (!actor?._id || !jeepneyId || !streamId || !Number.isSafeInteger(sequence) || sequence < 1) return null;
  const driver = await Driver.findOne({ userId: actor._id }).select('_id');
  if (!driver) return null;
  const filter = { driverId: driver._id, jeepneyId, status: 'scheduled',
    operatingMode: 'terminal_queue', terminalQueueStatus: 'off_queue' };
  const pending = await Trip.findOne(filter).select('_id routeId');
  if (!pending) return null;

  // Serialize progress and check-in with queue mutations, including concurrent fixes.
  return terminalQueue.transaction(pending.routeId, async session => {
    const trip = await Trip.findOne({ ...filter, _id: pending._id }).session(session);
    if (!trip) return null;
    const captured = capturedAt instanceof Date ? capturedAt : new Date(capturedAt);
    const time = captured.getTime();
    const priorTime = trip.terminalArrivalLastAt?.getTime();
    const sameStream = trip.terminalArrivalLastStreamId === streamId;
    if ((sameStream && sequence <= (trip.terminalArrivalLastSequence || 0)) ||
        (Number.isFinite(priorTime) && Number.isFinite(time) && time <= priorTime)) {
      return { tripId: String(trip._id), detected: false, ignored: true };
    }
    const coordinates = trip.terminalLocation?.coordinates || [];
    const coordinatesValid = validCoordinates(latitude, longitude) &&
      validCoordinates(coordinates[1], coordinates[0]);
    const distance = coordinatesValid
      ? haversineMeters(coordinates[1], coordinates[0], latitude, longitude) : null;
    const fresh = Number.isFinite(time) && time <= now.getTime() && now.getTime() - time <= MAX_FIX_AGE_MS;
    const accuracyValid = validNumber(accuracyMeters) && accuracyMeters >= 0 && accuracyMeters <= MAX_ACCURACY_METERS;
    const consecutive = sameStream && trip.terminalArrivalFixCount === 1 &&
      Number.isFinite(priorTime) && time > priorTime && time - priorTime <= MAX_FIX_AGE_MS;
    let status;
    let reason;
    if (!coordinatesValid) {
      status = 'invalid_coordinates'; reason = 'Location coordinates are invalid or the terminal location is unavailable';
    } else if (!fresh) {
      status = 'stale_location'; reason = 'Location data is stale or its timestamp is invalid';
    } else if (!accuracyValid) {
      status = 'poor_accuracy'; reason = 'GPS accuracy is too low';
    } else if (distance > (trip.terminalRadiusMeters || 75)) {
      status = 'outside_terminal_radius'; reason = `Driver is ${Math.round(distance)} meters from the terminal`;
    } else {
      status = consecutive ? 'accepted' : 'insufficient_valid_fixes';
      reason = consecutive ? 'Two valid GPS fixes received' : 'Only one valid GPS fix received';
    }
    const count = status === 'accepted' ? 2 : status === 'insufficient_valid_fixes' ? 1 : 0;
    trip.terminalArrivalFixCount = count;
    // Bad future timestamps cannot prevent recovery with the next real fix.
    if (Number.isFinite(time) && time <= now.getTime()) trip.terminalArrivalLastAt = captured;
    trip.terminalArrivalLastStreamId = streamId;
    trip.terminalArrivalLastSequence = sequence;
    trip.terminalArrivalStatus = status;
    trip.terminalArrivalReason = reason;
    trip.terminalArrivalLastDistanceMeters = distance ?? undefined;
    trip.terminalArrivalLastAccuracyMeters = validNumber(accuracyMeters) && accuracyMeters >= 0 ? accuracyMeters : undefined;
    await trip.save({ session });
    if (count < 2) return { tripId: String(trip._id), detected: false,
      fixes: count, distanceMeters: distance, reason, status };
    const queued = await terminalQueue.checkIn({
      session, existingId: trip._id, actor, requestId: `terminal-arrival-${trip._id}`,
      document: { driverId: trip.driverId, jeepneyId: trip.jeepneyId, routeId: trip.routeId,
        routePathSnapshot: trip.routePathSnapshot, terminalStopRef: trip.terminalStopRef,
        terminalLocation: trip.terminalLocation, terminalRadiusMeters: trip.terminalRadiusMeters },
    });
    return { ...queued.toObject(), terminalArrivalDetected: true, terminalArrivalDistanceMeters: distance };
  });
}

module.exports = { MAX_FIX_AGE_MS, MAX_ACCURACY_METERS, processTerminalArrival };
