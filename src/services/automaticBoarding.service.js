const {
  autoBoardingDriverLocationMaxAgeSeconds,
  autoBoardingDwellSeconds,
  autoBoardingPassengerLocationMaxAgeSeconds,
  autoBoardingProximityMeters,
} = require('../config/env');
const Passenger = require('../models/passenger');
const PickupRequest = require('../models/pickupRequest');
const TripSession = require('../models/tripSession');
const Jeepney = require('../models/jeepney');
const { haversineMeters } = require('../utils/geo');
const { evaluateAutoBoardingProximity } = require('../utils/automaticBoarding');
const {
  completeBoardingForPickupRequest,
} = require('./boarding.service');

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
  const age = now.getTime() - time.getTime();
  return age >= 0 && age <= Number(maxAgeSeconds || 0) * 1000;
};

const clearAutoBoardingWindow = async (pickupRequest, now) => {
  pickupRequest.autoBoarding = {
    proximityStartedAt: undefined,
    lastCheckedAt: now,
    lastDistanceMeters: undefined,
  };
  await pickupRequest.save();
};

const processAutomaticBoardingForRequest = async ({
  pickupRequest,
  trip,
  jeepneyLocation,
  now = new Date(),
}) => {
  if (!pickupRequest || (pickupRequest.partySize ?? 1) > 1 || pickupRequest.pickupType === 'terminal' || pickupRequest.status !== 'acknowledged') {
    return null;
  }
  if (!trip || trip.status !== 'active') {
    return null;
  }
  if (pickupRequest.expiresAt && now > new Date(pickupRequest.expiresAt)) {
    pickupRequest.status = 'expired';
    await pickupRequest.save();
    return null;
  }

  const passenger = await Passenger.findById(pickupRequest.passengerId).select(
    'lastKnownLocation lastSeenAt'
  );
  const passengerCoordinates = pointCoordinates(passenger?.lastKnownLocation);
  const jeepneyCoordinates = pointCoordinates(jeepneyLocation);
  if (
    !passengerCoordinates ||
    !jeepneyCoordinates ||
    !isFresh(passenger?.lastSeenAt, autoBoardingPassengerLocationMaxAgeSeconds, now)
  ) {
    return null;
  }

  const distanceMeters = haversineMeters(
    passengerCoordinates.latitude,
    passengerCoordinates.longitude,
    jeepneyCoordinates.latitude,
    jeepneyCoordinates.longitude
  );
  const evaluation = evaluateAutoBoardingProximity({
    distanceMeters,
    proximityStartedAt: pickupRequest.autoBoarding?.proximityStartedAt,
    now,
    proximityMeters: autoBoardingProximityMeters,
    dwellSeconds: autoBoardingDwellSeconds,
  });

  pickupRequest.autoBoarding = {
    proximityStartedAt: evaluation.proximityStartedAt || undefined,
    lastCheckedAt: now,
    lastDistanceMeters: Number(distanceMeters.toFixed(2)),
  };

  if (!evaluation.near) {
    await clearAutoBoardingWindow(pickupRequest, now);
    return null;
  }

  if (!evaluation.shouldBoard) {
    await pickupRequest.save();
    return null;
  }

  return completeBoardingForPickupRequest({
    pickupRequest,
    trip,
    passengerId: pickupRequest.passengerId,
    now,
    boardingMethod: 'auto_proximity',
    allowExisting: true,
  });
};

const processAutomaticBoardingForTrip = async ({
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
  if (!isFresh(jeepneySeenAt, autoBoardingDriverLocationMaxAgeSeconds, now)) {
    return [];
  }

  const requests = await PickupRequest.find({
    tripSessionId: trip._id,
    status: 'acknowledged',
  }).sort({ acknowledgedAt: 1, createdAt: 1 });

  const boarded = [];
  for (const request of requests) {
    const rideSession = await processAutomaticBoardingForRequest({
      pickupRequest: request,
      trip,
      jeepneyLocation: jeepneyPoint,
      now,
    });
    if (rideSession) {
      boarded.push(rideSession);
    }
  }
  return boarded;
};

const processAutomaticBoardingForPassenger = async ({
  passengerId,
  now = new Date(),
}) => {
  if (!passengerId) {
    return [];
  }
  const requests = await PickupRequest.find({
    passengerId,
    status: 'acknowledged',
  }).sort({ acknowledgedAt: 1, createdAt: 1 });

  const boarded = [];
  for (const request of requests) {
    const trip = await TripSession.findById(request.tripSessionId);
    if (!trip || trip.status !== 'active') {
      continue;
    }
    const jeepney = await Jeepney.findById(trip.jeepneyId).select(
      'lastKnownLocation lastSeenAt'
    );
    if (!isFresh(jeepney?.lastSeenAt, autoBoardingDriverLocationMaxAgeSeconds, now)) {
      continue;
    }
    const rideSession = await processAutomaticBoardingForRequest({
      pickupRequest: request,
      trip,
      jeepneyLocation: jeepney?.lastKnownLocation,
      now,
    });
    if (rideSession) {
      boarded.push(rideSession);
    }
  }
  return boarded;
};

module.exports = {
  processAutomaticBoardingForPassenger,
  processAutomaticBoardingForRequest,
  processAutomaticBoardingForTrip,
};
