const ApiError = require('../utils/apiError');

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const maxTrackedVehicles = 5000;
const maxPayloadBytes = 2048;
const maxPastAgeMs = 10 * 60 * 1000;
const maxFutureSkewMs = 30 * 1000;

const stateByJeepney = new Map();

const finiteNumber = (value, fieldName) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new ApiError(400, `${fieldName} must be a finite number`);
  }
  return parsed;
};

const optionalFiniteNumber = (value, fieldName) => {
  if (value == null) return null;
  return finiteNumber(value, fieldName);
};

const validateOrderedLocationPayload = (body = {}, now = new Date()) => {
  if (Buffer.byteLength(JSON.stringify(body), 'utf8') > maxPayloadBytes) {
    throw new ApiError(413, 'Location payload is too large');
  }

  const latitude = finiteNumber(body.latitude, 'latitude');
  const longitude = finiteNumber(body.longitude, 'longitude');
  if (latitude < -90 || latitude > 90) {
    throw new ApiError(400, 'latitude is out of range');
  }
  if (longitude < -180 || longitude > 180) {
    throw new ApiError(400, 'longitude is out of range');
  }

  const accuracyMeters = finiteNumber(body.accuracyMeters, 'accuracyMeters');
  if (accuracyMeters < 0 || accuracyMeters > 500) {
    throw new ApiError(400, 'accuracyMeters must be between 0 and 500');
  }

  const speedMetersPerSecond = optionalFiniteNumber(
    body.speedMetersPerSecond,
    'speedMetersPerSecond'
  );
  if (
    speedMetersPerSecond != null &&
    (speedMetersPerSecond < 0 || speedMetersPerSecond > 100)
  ) {
    throw new ApiError(
      400,
      'speedMetersPerSecond must be between 0 and 100'
    );
  }

  const headingDegrees = optionalFiniteNumber(
    body.headingDegrees,
    'headingDegrees'
  );
  if (
    headingDegrees != null &&
    (headingDegrees < 0 || headingDegrees >= 360)
  ) {
    throw new ApiError(400, 'headingDegrees must be between 0 and 360');
  }

  const streamId = String(body.streamId || '').trim();
  if (!uuidPattern.test(streamId)) {
    throw new ApiError(400, 'streamId must be a UUID');
  }

  const sequence = Number(body.sequence);
  if (!Number.isSafeInteger(sequence) || sequence < 1) {
    throw new ApiError(400, 'sequence must be a positive integer');
  }

  if (
    typeof body.capturedAt !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}T/.test(body.capturedAt)
  ) {
    throw new ApiError(400, 'capturedAt must be an ISO timestamp');
  }
  const capturedAt = new Date(body.capturedAt);
  if (Number.isNaN(capturedAt.getTime())) {
    throw new ApiError(400, 'capturedAt must be an ISO timestamp');
  }

  const nowMs = now.getTime();
  if (capturedAt.getTime() < nowMs - maxPastAgeMs) {
    throw new ApiError(400, 'capturedAt is too old');
  }
  if (capturedAt.getTime() > nowMs + maxFutureSkewMs) {
    throw new ApiError(400, 'capturedAt is too far in the future');
  }

  return {
    latitude,
    longitude,
    accuracyMeters,
    speedMetersPerSecond: speedMetersPerSecond ?? 0,
    headingDegrees: headingDegrees ?? 0,
    streamId,
    sequence,
    capturedAt,
  };
};

const removeOldestStateIfNeeded = () => {
  while (stateByJeepney.size >= maxTrackedVehicles) {
    let oldestKey = null;
    let oldestTouchedAt = Number.POSITIVE_INFINITY;
    for (const [key, state] of stateByJeepney) {
      if (state.touchedAt < oldestTouchedAt) {
        oldestKey = key;
        oldestTouchedAt = state.touchedAt;
      }
    }
    if (!oldestKey) return;
    stateByJeepney.delete(oldestKey);
  }
};

const reserveDriverLocationOrder = ({
  jeepneyId,
  streamId,
  sequence,
  capturedAt,
  serverReceivedAt,
}) => {
  const key = String(jeepneyId || '').trim();
  if (!key) {
    throw new ApiError(400, 'jeepneyId is required for location ordering');
  }

  const current = stateByJeepney.get(key);
  const capturedAtMs = capturedAt.getTime();
  if (current) {
    const sameStream = current.streamId === streamId;
    const staleSequence = sameStream && sequence <= current.sequence;
    const staleCapture = sameStream
      ? capturedAtMs < current.capturedAtMs
      : capturedAtMs <= current.capturedAtMs;
    if (staleSequence || staleCapture) {
      throw new ApiError(
        409,
        staleSequence
          ? 'Location sequence is stale'
          : 'Location stream is stale',
        [
          {
            accepted: false,
            streamId: current.streamId,
            sequence: current.sequence,
            serverReceivedAt: current.serverReceivedAt,
          },
        ]
      );
    }
  } else {
    removeOldestStateIfNeeded();
  }

  const serverReceivedAtIso = serverReceivedAt.toISOString();
  stateByJeepney.set(key, {
    streamId,
    sequence,
    capturedAtMs,
    serverReceivedAt: serverReceivedAtIso,
    touchedAt: serverReceivedAt.getTime(),
  });

  return {
    accepted: true,
    streamId,
    sequence,
    serverReceivedAt: serverReceivedAtIso,
  };
};

const buildPersistentLocationOrderFilter = ({
  jeepneyId,
  streamId,
  sequence,
  capturedAt,
}) => ({
  _id: jeepneyId,
  $or: [
    { 'latestLocationOrder.streamId': { $exists: false } },
    {
      'latestLocationOrder.streamId': streamId,
      'latestLocationOrder.sequence': { $lt: sequence },
      'latestLocationOrder.capturedAt': { $lte: capturedAt },
    },
    {
      'latestLocationOrder.streamId': { $ne: streamId },
      'latestLocationOrder.capturedAt': { $lt: capturedAt },
    },
  ],
});

const persistentLocationOrderUpdate = ({
  streamId,
  sequence,
  capturedAt,
  serverReceivedAt,
}) => ({
  streamId,
  sequence,
  capturedAt,
  serverReceivedAt,
});

const stalePersistentLocationError = (latestLocationOrder = {}) =>
  new ApiError(
    409,
    latestLocationOrder.streamId
      ? latestLocationOrder.streamId === latestLocationOrder.proposedStreamId
        ? 'Location sequence is stale'
        : 'Location stream is stale'
      : 'Location update is stale',
    [
      {
        accepted: false,
        streamId: latestLocationOrder.streamId || null,
        sequence: latestLocationOrder.sequence || null,
        serverReceivedAt: latestLocationOrder.serverReceivedAt
          ? new Date(latestLocationOrder.serverReceivedAt).toISOString()
          : null,
      },
    ]
  );

const rememberPersistedDriverLocationOrder = ({
  jeepneyId,
  streamId,
  sequence,
  capturedAt,
  serverReceivedAt,
}) => {
  const key = String(jeepneyId);
  if (!stateByJeepney.has(key)) {
    removeOldestStateIfNeeded();
  }
  stateByJeepney.set(key, {
    streamId,
    sequence,
    capturedAtMs: capturedAt.getTime(),
    serverReceivedAt: serverReceivedAt.toISOString(),
    touchedAt: serverReceivedAt.getTime(),
  });
};

const clearDriverLocationOrderingState = () => {
  stateByJeepney.clear();
};

const hasDriverLocationOrderingState = (jeepneyId) =>
  stateByJeepney.has(String(jeepneyId || '').trim());

module.exports = {
  validateOrderedLocationPayload,
  reserveDriverLocationOrder,
  buildPersistentLocationOrderFilter,
  persistentLocationOrderUpdate,
  stalePersistentLocationError,
  rememberPersistedDriverLocationOrder,
  hasDriverLocationOrderingState,
  clearDriverLocationOrderingState,
  maxPayloadBytes,
  maxTrackedVehicles,
};
