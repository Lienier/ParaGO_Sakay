const Trip = require('../models/tripSession');
const Driver = require('../models/driver');
const { haversineMeters } = require('../utils/geo');
const terminalQueue = require('./terminalQueue.service');

const MAX_FIX_AGE_MS = 60 * 1000;
const MAX_ACCURACY_METERS = 50;

const pointCoordinates = (point) =>
  Array.isArray(point?.coordinates) && point.coordinates.length >= 2
    ? [Number(point.coordinates[0]), Number(point.coordinates[1])]
    : null;

const isFresh = (capturedAt, now) =>
  capturedAt instanceof Date &&
  !Number.isNaN(capturedAt.getTime()) &&
  capturedAt.getTime() <= now.getTime() &&
  now.getTime() - capturedAt.getTime() <= MAX_FIX_AGE_MS;

const updateArrivalState = async ({
  trip,
  streamId,
  sequence,
  capturedAt,
  count,
}) =>
  Trip.findOneAndUpdate(
    {
      _id: trip._id,
      status: 'scheduled',
      operatingMode: 'terminal_queue',
      terminalQueueStatus: 'off_queue',
      $or: [
        { terminalArrivalLastSequence: { $exists: false } },
        { terminalArrivalLastSequence: { $lt: sequence } },
      ],
    },
    {
      $set: {
        terminalArrivalFixCount: count,
        terminalArrivalLastAt: capturedAt,
        terminalArrivalLastStreamId: streamId,
        terminalArrivalLastSequence: sequence,
      },
    },
    { new: true }
  );

const resetArrivalState = async ({
  trip,
  streamId,
  sequence,
  capturedAt,
}) =>
  updateArrivalState({
    trip,
    streamId,
    sequence,
    capturedAt,
    count: 0,
  });

const processTerminalArrival = async ({
  actor,
  jeepneyId,
  latitude,
  longitude,
  accuracyMeters,
  streamId,
  sequence,
  capturedAt,
  now = new Date(),
}) => {
  if (!actor?._id || !jeepneyId || !streamId || !Number.isSafeInteger(sequence)) {
    return null;
  }

  const driver = await Driver.findOne({ userId: actor._id }).select('_id');
  if (!driver) return null;
  const trip = await Trip.findOne({
    driverId: driver._id,
    jeepneyId,
    status: 'scheduled',
    operatingMode: 'terminal_queue',
    terminalQueueStatus: 'off_queue',
  });
  if (!trip) return null;

  const terminal = pointCoordinates(trip.terminalLocation);
  const captured = capturedAt instanceof Date ? capturedAt : new Date(capturedAt);
  const accuracy = Number(accuracyMeters);
  const distance = terminal
    ? haversineMeters(terminal[1], terminal[0], Number(latitude), Number(longitude))
    : Number.POSITIVE_INFINITY;
  const radius = Math.max(1, Number(trip.terminalRadiusMeters || 75));
  const inside =
    terminal &&
    Number.isFinite(accuracy) &&
    accuracy <= MAX_ACCURACY_METERS &&
    isFresh(captured, now) &&
    Number.isFinite(distance) &&
    distance <= radius;

  if (!inside) {
    await resetArrivalState({
      trip,
      streamId,
      sequence,
      capturedAt: captured,
    });
    return { tripId: String(trip._id), detected: false, distanceMeters: distance };
  }

  const priorCount = Number(trip.terminalArrivalFixCount || 0);
  const priorAt = trip.terminalArrivalLastAt;
  const sameStream = trip.terminalArrivalLastStreamId === streamId;
  const consecutive =
    priorCount === 1 &&
    sameStream &&
    priorAt instanceof Date &&
    captured.getTime() - priorAt.getTime() <= MAX_FIX_AGE_MS &&
    sequence > Number(trip.terminalArrivalLastSequence || 0);

  let updated;
  if (consecutive) {
    updated = await updateArrivalState({
      trip,
      streamId,
      sequence,
      capturedAt: captured,
      count: 2,
    });
  } else if (priorCount >= 2 && sameStream && sequence >= Number(trip.terminalArrivalLastSequence || 0)) {
    updated = trip;
  } else {
    updated = await updateArrivalState({
      trip,
      streamId,
      sequence,
      capturedAt: captured,
      count: 1,
    });
  }

  if (!updated) {
    const current = await Trip.findById(trip._id);
    if (!current || current.status !== 'scheduled') return current;
    if (
      Number(current.terminalArrivalFixCount || 0) >= 2 &&
      current.terminalArrivalLastStreamId === streamId
    ) {
      updated = current;
    } else {
      return current;
    }
  }

  if (Number(updated.terminalArrivalFixCount || 0) < 2) {
    return {
      tripId: String(updated._id),
      detected: false,
      fixes: Number(updated.terminalArrivalFixCount || 0),
      distanceMeters: distance,
    };
  }

  const requestId = `terminal-arrival-${updated._id}-${sequence}`;
  const queued = await terminalQueue.checkIn({
    existingId: updated._id,
    actor,
    requestId,
    document: {
      driverId: updated.driverId,
      jeepneyId: updated.jeepneyId,
      routeId: updated.routeId,
      routePathSnapshot: updated.routePathSnapshot,
      terminalStopRef: updated.terminalStopRef,
      terminalLocation: updated.terminalLocation,
      terminalRadiusMeters: updated.terminalRadiusMeters,
    },
  });
  return {
    ...queued.toObject(),
    terminalArrivalDetected: true,
    terminalArrivalDistanceMeters: distance,
  };
};

module.exports = {
  MAX_FIX_AGE_MS,
  MAX_ACCURACY_METERS,
  processTerminalArrival,
};
