const { haversineMeters } = require('./geo');

const EARTH_RADIUS_METERS = 6371000;

const readDestinationPoint = (ride) => {
  const coordinates = Array.isArray(ride?.destinationLocation?.coordinates)
    ? ride.destinationLocation.coordinates
    : [];
  if (coordinates.length < 2) {
    return null;
  }

  const longitude = Number(coordinates[0]);
  const latitude = Number(coordinates[1]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  return { latitude, longitude };
};

const hasValidDestinationPoint = (ride) => readDestinationPoint(ride) !== null;

const hasFiniteLatLng = (latitude, longitude) =>
  Number.isFinite(Number(latitude)) && Number.isFinite(Number(longitude));

const buildPoint = (latitude, longitude) => {
  if (!hasFiniteLatLng(latitude, longitude)) {
    return null;
  }
  return {
    latitude: Number(latitude),
    longitude: Number(longitude),
  };
};

const distanceMetersToDestination = ({ ride, latitude, longitude }) => {
  const finalPoint = readDestinationPoint(ride);
  if (!finalPoint || !hasFiniteLatLng(latitude, longitude)) {
    return Number.POSITIVE_INFINITY;
  }

  return haversineMeters(
    Number(latitude),
    Number(longitude),
    finalPoint.latitude,
    finalPoint.longitude
  );
};

const projectPointToMeters = (point, referenceLatitude) => {
  const latitudeRadians = (Number(point.latitude) * Math.PI) / 180;
  const longitudeRadians = (Number(point.longitude) * Math.PI) / 180;
  const referenceLatitudeRadians = (Number(referenceLatitude) * Math.PI) / 180;

  return {
    x: EARTH_RADIUS_METERS * longitudeRadians * Math.cos(referenceLatitudeRadians),
    y: EARTH_RADIUS_METERS * latitudeRadians,
  };
};

const distancePointToSegmentMeters = ({
  point,
  segmentStart,
  segmentEnd,
}) => {
  if (!point || !segmentStart || !segmentEnd) {
    return Number.POSITIVE_INFINITY;
  }

  const referenceLatitude =
    (point.latitude + segmentStart.latitude + segmentEnd.latitude) / 3;
  const pointMeters = projectPointToMeters(point, referenceLatitude);
  const startMeters = projectPointToMeters(segmentStart, referenceLatitude);
  const endMeters = projectPointToMeters(segmentEnd, referenceLatitude);
  const deltaX = endMeters.x - startMeters.x;
  const deltaY = endMeters.y - startMeters.y;
  const segmentLengthSquared = deltaX * deltaX + deltaY * deltaY;

  if (segmentLengthSquared <= 0) {
    return Math.hypot(
      pointMeters.x - startMeters.x,
      pointMeters.y - startMeters.y
    );
  }

  const projection =
    ((pointMeters.x - startMeters.x) * deltaX +
      (pointMeters.y - startMeters.y) * deltaY) /
    segmentLengthSquared;
  const clampedProjection = Math.max(0, Math.min(1, projection));
  const closestX = startMeters.x + deltaX * clampedProjection;
  const closestY = startMeters.y + deltaY * clampedProjection;

  return Math.hypot(pointMeters.x - closestX, pointMeters.y - closestY);
};

const computeApproachLeadMeters = ({
  previousLatitude,
  previousLongitude,
  latitude,
  longitude,
  thresholdMeters,
}) => {
  const previousPoint = buildPoint(previousLatitude, previousLongitude);
  const currentPoint = buildPoint(latitude, longitude);
  const normalizedThreshold = Number(thresholdMeters);
  if (!previousPoint || !currentPoint || !Number.isFinite(normalizedThreshold)) {
    return 0;
  }

  const movementMeters = haversineMeters(
    previousPoint.latitude,
    previousPoint.longitude,
    currentPoint.latitude,
    currentPoint.longitude
  );
  const maxLeadMeters = Math.max(15, normalizedThreshold * 0.5);
  return Math.min(Math.max(movementMeters, 0), maxLeadMeters);
};

const isRideWithinDestinationApproachThreshold = ({
  ride,
  latitude,
  longitude,
  thresholdMeters,
  previousLatitude,
  previousLongitude,
}) => {
  if (
    !hasFiniteLatLng(latitude, longitude) ||
    !Number.isFinite(Number(thresholdMeters))
  ) {
    return false;
  }

  const finalPoint = readDestinationPoint(ride);
  if (!finalPoint) {
    return false;
  }

  const normalizedThreshold = Number(thresholdMeters);
  const currentDistanceMeters = distanceMetersToDestination({
    ride,
    latitude,
    longitude,
  });
  if (currentDistanceMeters <= normalizedThreshold) {
    return true;
  }

  const previousPoint = buildPoint(previousLatitude, previousLongitude);
  const currentPoint = buildPoint(latitude, longitude);
  if (!previousPoint || !currentPoint) {
    return false;
  }

  const pathDistanceMeters = distancePointToSegmentMeters({
    point: finalPoint,
    segmentStart: previousPoint,
    segmentEnd: currentPoint,
  });
  if (pathDistanceMeters <= normalizedThreshold) {
    return true;
  }

  const leadMeters = computeApproachLeadMeters({
    previousLatitude,
    previousLongitude,
    latitude,
    longitude,
    thresholdMeters: normalizedThreshold,
  });
  return currentDistanceMeters <= normalizedThreshold + leadMeters;
};

const buildDestinationApproachPayload = ({
  ride,
  thresholdMeters,
  triggeredAt,
}) => ({
  rideSessionId: ride?._id?.toString() || ride?.id?.toString() || '',
  tripSessionId: ride?.tripSessionId?.toString() || '',
  passengerId: ride?.passengerId?.toString() || '',
  destinationStopRef: ride?.destinationStopRef?.toString() || '',
  thresholdMeters: Number(thresholdMeters),
  triggeredAt:
    triggeredAt instanceof Date
      ? triggeredAt.toISOString()
      : new Date(triggeredAt || Date.now()).toISOString(),
});

module.exports = {
  buildDestinationApproachPayload,
  computeApproachLeadMeters,
  distanceMetersToDestination,
  distancePointToSegmentMeters,
  hasValidDestinationPoint,
  isRideWithinDestinationApproachThreshold,
  readDestinationPoint,
};
