const { createTripRecord } = require('./tripLifecycle.service');
const ApiError = require('../utils/apiError');
const Route = require('../models/route');
const StopAlert = require('../models/stopAlert');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const {
  stopAlertCooldownMinutes,
  unloadRoadProximityMeters,
} = require('../config/env');
const {
  isRoutePickupNearRoad,
  pickDefaultRouteCoordinate,
} = require('../utils/routeGeo');

const createStopAlert = async ({
  passengerId,
  tripSessionId,
  stopRef,
  note,
  location,
}) => {
  const session = await RideSession.findOne({
    passengerId,
    tripSessionId,
    status: 'onboard',
    canSendStopAlert: true,
  });
  if (!session) {
    throw new ApiError(403, 'No onboard verified ride session for stop alert');
  }

  const recent = await StopAlert.findOne({
    passengerId,
    tripSessionId,
    status: 'sent',
    createdAt: { $gte: new Date(Date.now() - stopAlertCooldownMinutes * 60 * 1000) },
  });
  if (recent) {
    throw new ApiError(429, 'Please wait before sending another stop alert');
  }

  const trip = await TripSession.findById(tripSessionId).select('routeId status');
  if (!trip) throw new ApiError(404, 'Trip session not found');
  if (trip.status !== 'active') {
    throw new ApiError(409, 'Trip session is not active');
  }

  const route = await Route.findById(trip.routeId);
  if (!route) {
    throw new ApiError(404, 'Route not found for this trip');
  }

  if (session.flowVersion === 2) {
    const member = session.members.find(m => m.status === 'onboard' && m.destinationStopRef === stopRef);
    if (!member) throw new ApiError(400, 'Select a remaining passenger destination for the para alert.');
    location = member.destinationLocation;
  }
  let alertLocation = location;
  if (!alertLocation || !Array.isArray(alertLocation.coordinates) || alertLocation.coordinates.length < 2) {
    alertLocation = pickDefaultRouteCoordinate(route);
  }
  if (!alertLocation) {
    throw new ApiError(400, 'location is required for this route');
  }

  const [lng, lat] = alertLocation.coordinates;
  if (
    !isRoutePickupNearRoad({
      latitude: lat,
      longitude: lng,
      route,
      maxDistanceMeters: unloadRoadProximityMeters,
    })
  ) {
    throw new ApiError(
      400,
      `Unload point must be within ${unloadRoadProximityMeters} meters of the route`
    );
  }

  return createTripRecord(StopAlert, {
    passengerId,
    tripSessionId,
    rideSessionId: session._id,
    routeId: trip.routeId,
    stopRef,
    note,
    location: alertLocation,
    status: 'sent',
  }, { beforeCreate: async transaction => {
    // The trip write serializes competing alerts. Recheck inside the retried
    // transaction so simultaneous taps cannot all pass the initial lookup.
    const duplicate = await StopAlert.findOne({ passengerId, tripSessionId,
      status: 'sent', createdAt: { $gte: new Date(Date.now() - stopAlertCooldownMinutes * 60 * 1000) },
    }).session(transaction);
    if (duplicate) throw new ApiError(429, 'Please wait before sending another stop alert');
  } });
};

module.exports = { createStopAlert };
