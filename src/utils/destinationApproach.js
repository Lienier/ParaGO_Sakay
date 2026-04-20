const { haversineMeters } = require('./geo');

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

const isRideWithinDestinationApproachThreshold = ({
  ride,
  latitude,
  longitude,
  thresholdMeters,
}) => {
  if (
    !Number.isFinite(Number(latitude)) ||
    !Number.isFinite(Number(longitude)) ||
    !Number.isFinite(Number(thresholdMeters))
  ) {
    return false;
  }

  const finalPoint = readDestinationPoint(ride);
  if (!finalPoint) {
    return false;
  }

  const distanceMeters = haversineMeters(
    Number(latitude),
    Number(longitude),
    finalPoint.latitude,
    finalPoint.longitude
  );
  return distanceMeters <= Number(thresholdMeters);
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
  hasValidDestinationPoint,
  isRideWithinDestinationApproachThreshold,
  readDestinationPoint,
};
