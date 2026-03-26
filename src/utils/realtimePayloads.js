const toIsoString = (value) => {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

const normalizePoint = (value, fieldName) => {
  const coordinates = Array.isArray(value?.coordinates)
    ? value.coordinates.map((entry) => Number(entry))
    : [];
  if (coordinates.length < 2) {
    return undefined;
  }
  return {
    type: value?.type === 'Point' ? 'Point' : 'Point',
    coordinates,
  };
};

const serializePickupRequest = (request) => {
  if (!request) return null;
  return {
    _id: request._id?.toString() || '',
    passengerId: request.passengerId?.toString() || '',
    tripSessionId: request.tripSessionId?.toString() || '',
    routeId: request.routeId?.toString() || '',
    status: request.status?.toString() || '',
    stopRef: request.stopRef?.toString() || null,
    sourceNote: request.sourceNote?.toString() || null,
    pickupLocation: normalizePoint(request.pickupLocation, 'pickupLocation'),
    destinationStopRef: request.destinationStopRef?.toString() || null,
    destinationLocation: normalizePoint(
      request.destinationLocation,
      'destinationLocation'
    ),
    expiresAt: toIsoString(request.expiresAt),
    createdAt: toIsoString(request.createdAt),
    acknowledgedAt: toIsoString(request.acknowledgedAt),
  };
};

const serializeRideSession = (session) => {
  if (!session) return null;
  return {
    _id: session._id?.toString() || '',
    passengerId: session.passengerId?.toString() || '',
    tripSessionId: session.tripSessionId?.toString() || '',
    pickupRequestId: session.pickupRequestId?.toString() || '',
    destinationStopRef: session.destinationStopRef?.toString() || null,
    destinationLocation: normalizePoint(
      session.destinationLocation,
      'destinationLocation'
    ),
    status: session.status?.toString() || '',
    canSendStopAlert:
      typeof session.canSendStopAlert === 'boolean'
        ? session.canSendStopAlert
        : null,
    boardedAt: toIsoString(session.boardedAt),
    endedAt: toIsoString(session.endedAt),
    createdAt: toIsoString(session.createdAt),
  };
};

const serializeStopAlert = (alert) => {
  if (!alert) return null;
  return {
    _id: alert._id?.toString() || '',
    passengerId: alert.passengerId?.toString() || '',
    tripSessionId: alert.tripSessionId?.toString() || '',
    routeId: alert.routeId?.toString() || '',
    rideSessionId: alert.rideSessionId?.toString() || '',
    status: alert.status?.toString() || '',
    stopRef: alert.stopRef?.toString() || '',
    note: alert.note?.toString() || null,
    location: normalizePoint(alert.location, 'location'),
    createdAt: toIsoString(alert.createdAt),
    acknowledgedAt: toIsoString(alert.acknowledgedAt),
  };
};

module.exports = {
  serializePickupRequest,
  serializeRideSession,
  serializeStopAlert,
};
