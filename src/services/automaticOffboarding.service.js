const {
  autoOffboardingConsecutiveOutsideChecks,
  autoOffboardingDistanceMeters,
  autoOffboardingDriverLocationMaxAgeSeconds,
  autoOffboardingPassengerLocationMaxAgeSeconds,
  autoOffboardingSustainedSeparationSeconds,
} = require('../config/env');
const Jeepney = require('../models/jeepney');
const Passenger = require('../models/passenger');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const { haversineMeters } = require('../utils/geo');
const {
  evaluateAutoOffboardingSeparation,
} = require('../utils/automaticOffboarding');
const { completeRideSession } = require('./rideCompletion.service');

const pointCoordinates = (value) => {
  const coordinates = Array.isArray(value?.coordinates) ? value.coordinates : [];
  if (coordinates.length < 2) {
    return null;
  }
  const longitude = Number(coordinates[0]);
  const latitude = Number(coordinates[1]);
  if (
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  return { latitude, longitude };
};

const isFresh = (value, maxAgeSeconds, now) => {
  if (!value) {
    return false;
  }
  const time = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(time.getTime())) {
    return false;
  }
  return now.getTime() - time.getTime() <= Number(maxAgeSeconds || 0) * 1000;
};

const resetAutoOffboardingWindow = async (ride, now) => {
  ride.autoOffboarding = {
    separationStartedAt: undefined,
    lastCheckedAt: now,
    lastDistanceMeters: undefined,
    outsideCount: 0,
  };
  await ride.save();
};

const processAutomaticOffboardingForRide = async ({
  ride,
  trip,
  jeepneyLocation,
  now = new Date(),
}) => {
  if (!ride || ride.status !== 'onboard') {
    return null;
  }
  if (!trip || trip.status !== 'active') {
    return null;
  }

  const passenger = await Passenger.findById(ride.passengerId).select(
    'lastKnownLocation lastSeenAt'
  );
  const passengerCoordinates = pointCoordinates(passenger?.lastKnownLocation);
  const jeepneyCoordinates = pointCoordinates(jeepneyLocation);
  if (
    !passengerCoordinates ||
    !jeepneyCoordinates ||
    !isFresh(
      passenger?.lastSeenAt,
      autoOffboardingPassengerLocationMaxAgeSeconds,
      now
    )
  ) {
    return null;
  }

  const distanceMeters = haversineMeters(
    passengerCoordinates.latitude,
    passengerCoordinates.longitude,
    jeepneyCoordinates.latitude,
    jeepneyCoordinates.longitude
  );
  const evaluation = evaluateAutoOffboardingSeparation({
    distanceMeters,
    separationStartedAt: ride.autoOffboarding?.separationStartedAt,
    outsideCount: ride.autoOffboarding?.outsideCount,
    now,
    separationMeters: autoOffboardingDistanceMeters,
    consecutiveOutsideChecks: autoOffboardingConsecutiveOutsideChecks,
    sustainedSeparationSeconds: autoOffboardingSustainedSeparationSeconds,
  });

  if (!evaluation.outside) {
    await resetAutoOffboardingWindow(ride, now);
    return null;
  }

  ride.autoOffboarding = {
    separationStartedAt: evaluation.separationStartedAt || undefined,
    lastCheckedAt: now,
    lastDistanceMeters: Number(distanceMeters.toFixed(2)),
    outsideCount: evaluation.outsideCount,
  };

  if (!evaluation.shouldOffboard) {
    await ride.save();
    return null;
  }

  return completeRideSession({
    session: ride,
    trip,
    actorRole: 'system',
    completionMethod: 'auto_separation',
  });
};

const processAutomaticOffboardingForTrip = async ({
  tripSessionId,
  jeepneyLocation,
  now = new Date(),
}) => {
  if (!tripSessionId) {
    return [];
  }
  const trip = await TripSession.findById(tripSessionId);
  if (!trip || trip.status !== 'active') {
    return [];
  }

  const resolvedJeepneyLocation =
    jeepneyLocation ||
    (await Jeepney.findById(trip.jeepneyId).select('lastKnownLocation lastSeenAt'));
  const jeepneyPoint = resolvedJeepneyLocation?.lastKnownLocation
    ? resolvedJeepneyLocation.lastKnownLocation
    : resolvedJeepneyLocation;
  const jeepneySeenAt = resolvedJeepneyLocation?.lastSeenAt || now;
  if (!isFresh(jeepneySeenAt, autoOffboardingDriverLocationMaxAgeSeconds, now)) {
    return [];
  }

  const rides = await RideSession.find({
    tripSessionId: trip._id,
    status: 'onboard',
  }).sort({ boardedAt: 1, createdAt: 1 });

  const completed = [];
  for (const ride of rides) {
    const completedRide = await processAutomaticOffboardingForRide({
      ride,
      trip,
      jeepneyLocation: jeepneyPoint,
      now,
    });
    if (completedRide) {
      completed.push(completedRide);
    }
  }
  return completed;
};

const processAutomaticOffboardingForPassenger = async ({
  passengerId,
  now = new Date(),
}) => {
  if (!passengerId) {
    return [];
  }
  const rides = await RideSession.find({
    passengerId,
    status: 'onboard',
  }).sort({ boardedAt: 1, createdAt: 1 });

  const completed = [];
  for (const ride of rides) {
    const trip = await TripSession.findById(ride.tripSessionId);
    if (!trip || trip.status !== 'active') {
      continue;
    }
    const jeepney = await Jeepney.findById(trip.jeepneyId).select(
      'lastKnownLocation lastSeenAt'
    );
    if (!isFresh(jeepney?.lastSeenAt, autoOffboardingDriverLocationMaxAgeSeconds, now)) {
      continue;
    }
    const completedRide = await processAutomaticOffboardingForRide({
      ride,
      trip,
      jeepneyLocation: jeepney?.lastKnownLocation,
      now,
    });
    if (completedRide) {
      completed.push(completedRide);
    }
  }
  return completed;
};

module.exports = {
  processAutomaticOffboardingForPassenger,
  processAutomaticOffboardingForRide,
  processAutomaticOffboardingForTrip,
};
