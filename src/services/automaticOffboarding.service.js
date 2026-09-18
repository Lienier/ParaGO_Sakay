const {
  autoOffboardingConsecutiveOutsideChecks,
  autoOffboardingDistanceMeters,
  autoOffboardingDriverLocationMaxAgeSeconds,
  autoOffboardingPassengerLocationMaxAgeSeconds,
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

const MAX_AUTOMATION_LOCATION_AGE_SECONDS = 15;

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
  const configuredMaxAge = Number(maxAgeSeconds);
  const maxAgeSecondsAtMost15 = Number.isFinite(configuredMaxAge)
    ? Math.min(configuredMaxAge, MAX_AUTOMATION_LOCATION_AGE_SECONDS)
    : MAX_AUTOMATION_LOCATION_AGE_SECONDS;
  const age = now.getTime() - time.getTime();
  return age >= 0 && age <= maxAgeSecondsAtMost15 * 1000;
};

const processAutomaticOffboardingForRide = async ({
  ride,
  trip,
  jeepneyLocation,
  now = new Date(),
}) => {
  if (!ride || (ride.partySize ?? 1) > 1 || ride.status !== 'onboard') {
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

  // One passenger GPS observation counts at most once, even when both
  // passenger and driver requests evaluate the ride concurrently.
  const sampleAt = new Date(passenger.lastSeenAt);
  const distanceMeters = haversineMeters(
    passengerCoordinates.latitude, passengerCoordinates.longitude,
    jeepneyCoordinates.latitude, jeepneyCoordinates.longitude
  );
  const previous = ride.autoOffboarding || {};
  if (previous.lastPassengerSampleAt && sampleAt <= new Date(previous.lastPassengerSampleAt)) return null;
  const interrupted = previous.lastCheckedAt && now - new Date(previous.lastCheckedAt) > 15000;
  const evaluation = evaluateAutoOffboardingSeparation({
    distanceMeters,
    separationStartedAt: interrupted ? null : previous.separationStartedAt,
    outsideCount: interrupted ? 0 : previous.outsideCount,
    now, separationMeters: autoOffboardingDistanceMeters,
    consecutiveOutsideChecks: autoOffboardingConsecutiveOutsideChecks,
  });
  const updated = await RideSession.findOneAndUpdate({
    _id: ride._id, status: 'onboard',
    'autoOffboarding.lastPassengerSampleAt': previous.lastPassengerSampleAt || { $exists: false },
  }, { $set: { autoOffboarding: {
    lastPassengerSampleAt: sampleAt,
    separationStartedAt: evaluation.separationStartedAt || undefined,
    lastCheckedAt: now, lastDistanceMeters: Number(distanceMeters.toFixed(2)),
    outsideCount: evaluation.outsideCount,
  } } }, { new: true });
  if (!updated || !evaluation.shouldOffboard) return null;

  return completeRideSession({
    session: updated,
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
