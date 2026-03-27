const Driver = require('../models/driver');
const Passenger = require('../models/passenger');
const TripSession = require('../models/tripSession');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const ApiError = require('../utils/apiError');

const applyQueryOptions = (query, { select, populate } = {}) => {
  if (select) {
    query.select(select);
  }

  if (Array.isArray(populate)) {
    for (const entry of populate) {
      query.populate(entry);
    }
  } else if (populate) {
    query.populate(populate);
  }

  return query;
};

const requireCurrentDriver = async (
  user,
  {
    select,
    populate,
    notFoundMessage = 'Driver profile missing',
  } = {}
) => {
  const query = Driver.findOne({ userId: user._id });
  applyQueryOptions(query, { select, populate });
  const driver = await query;
  if (!driver) {
    throw new ApiError(404, notFoundMessage);
  }
  return driver;
};

const requireCurrentPassenger = async (
  user,
  {
    select,
    populate,
    notFoundMessage = 'Passenger profile missing',
  } = {}
) => {
  const query = Passenger.findOne({ userId: user._id });
  applyQueryOptions(query, { select, populate });
  const passenger = await query;
  if (!passenger) {
    throw new ApiError(404, notFoundMessage);
  }
  return passenger;
};

const requireTrip = async (
  tripId,
  {
    select,
    populate,
    notFoundMessage = 'Trip not found',
  } = {}
) => {
  const query = TripSession.findById(tripId);
  applyQueryOptions(query, { select, populate });
  const trip = await query;
  if (!trip) {
    throw new ApiError(404, notFoundMessage);
  }
  return trip;
};

const requirePickupRequest = async (
  pickupRequestId,
  {
    select,
    populate,
    notFoundMessage = 'Pickup request not found',
  } = {}
) => {
  const query = PickupRequest.findById(pickupRequestId);
  applyQueryOptions(query, { select, populate });
  const request = await query;
  if (!request) {
    throw new ApiError(404, notFoundMessage);
  }
  return request;
};

const requireRideSession = async (
  rideSessionId,
  {
    select,
    populate,
    notFoundMessage = 'Ride session not found',
  } = {}
) => {
  const query = RideSession.findById(rideSessionId);
  applyQueryOptions(query, { select, populate });
  const session = await query;
  if (!session) {
    throw new ApiError(404, notFoundMessage);
  }
  return session;
};

const ensureDriverAssignedToTrip = async (
  user,
  trip,
  {
    driver,
    notFoundMessage = 'Driver profile missing',
    forbiddenMessage = 'You are not assigned to this trip',
  } = {}
) => {
  const resolvedDriver =
    driver ??
    (await requireCurrentDriver(user, {
      notFoundMessage,
    }));

  if (String(resolvedDriver._id) !== String(trip.driverId)) {
    throw new ApiError(403, forbiddenMessage);
  }

  return resolvedDriver;
};

const ensurePassengerOwnsPickupRequest = async (
  user,
  request,
  {
    passenger,
    notFoundMessage = 'Passenger profile missing',
    forbiddenMessage = 'You can only manage your own pickup request',
  } = {}
) => {
  const resolvedPassenger =
    passenger ??
    (await requireCurrentPassenger(user, {
      notFoundMessage,
    }));

  if (String(request.passengerId) !== String(resolvedPassenger._id)) {
    throw new ApiError(403, forbiddenMessage);
  }

  return resolvedPassenger;
};

const ensurePassengerOwnsRideSession = async (
  user,
  session,
  {
    passenger,
    notFoundMessage = 'Passenger profile missing',
    forbiddenMessage = 'You can only manage your own ride session',
  } = {}
) => {
  const resolvedPassenger =
    passenger ??
    (await requireCurrentPassenger(user, {
      notFoundMessage,
    }));

  if (String(session.passengerId) !== String(resolvedPassenger._id)) {
    throw new ApiError(403, forbiddenMessage);
  }

  return resolvedPassenger;
};

module.exports = {
  requireCurrentDriver,
  requireCurrentPassenger,
  requireTrip,
  requirePickupRequest,
  requireRideSession,
  ensureDriverAssignedToTrip,
  ensurePassengerOwnsPickupRequest,
  ensurePassengerOwnsRideSession,
};
