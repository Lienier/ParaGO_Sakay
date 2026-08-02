const Driver = require('../models/driver');
const Passenger = require('../models/passenger');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const Route = require('../models/route');
const TripSession = require('../models/tripSession');
const { ADMIN, DRIVER, PASSENGER } = require('../constants/roles');

const authorizeRouteSubscription = async ({ user, routeId }) => {
  const route = await Route.findById(routeId).select('_id status');
  if (!route) {
    return { allowed: false, code: 'NOT_FOUND' };
  }

  if (user.role === ADMIN) {
    return { allowed: true };
  }

  if (user.role === PASSENGER && route.status === 'active') {
    return { allowed: true };
  }

  if (user.role === DRIVER && route.status === 'active') {
    const assigned = await Driver.exists({
      userId: user.id,
      assignedRouteId: route._id,
      status: 'active',
    });
    return assigned
      ? { allowed: true }
      : { allowed: false, code: 'FORBIDDEN' };
  }

  return { allowed: false, code: 'FORBIDDEN' };
};

const authorizeTripSubscription = async ({ user, tripId }) => {
  const trip = await TripSession.findById(tripId).select(
    '_id driverId routeId status'
  );
  if (!trip) {
    return { allowed: false, code: 'NOT_FOUND' };
  }

  if (user.role === ADMIN) {
    return { allowed: true };
  }

  if (!['scheduled', 'active'].includes(trip.status)) {
    return { allowed: false, code: 'FORBIDDEN' };
  }

  if (user.role === DRIVER) {
    const driver = await Driver.findOne({ userId: user.id }).select('_id');
    return driver && String(driver._id) === String(trip.driverId)
      ? { allowed: true }
      : { allowed: false, code: 'FORBIDDEN' };
  }

  if (user.role === PASSENGER) {
    const passenger = await Passenger.findOne({ userId: user.id }).select('_id');
    if (!passenger) {
      return { allowed: false, code: 'FORBIDDEN' };
    }

    const [pickup, ride] = await Promise.all([
      PickupRequest.exists({
        passengerId: passenger._id,
        tripSessionId: trip._id,
        status: { $in: ['pending', 'acknowledged'] },
      }),
      RideSession.exists({
        passengerId: passenger._id,
        tripSessionId: trip._id,
        status: { $in: ['waiting', 'onboard'] },
      }),
    ]);

    return pickup || ride
      ? { allowed: true }
      : { allowed: false, code: 'FORBIDDEN' };
  }

  return { allowed: false, code: 'FORBIDDEN' };
};

module.exports = {
  authorizeRouteSubscription,
  authorizeTripSubscription,
};
