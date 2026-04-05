const express = require('express');
const TripSession = require('../models/tripSession');
const Jeepney = require('../models/jeepney');
const Route = require('../models/route');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { DRIVER, ADMIN, PASSENGER } = require('../constants/roles');
const { ensureObjectId, ensureEnum } = require('../utils/validators');
const {
  requireCurrentDriver,
  requireTrip,
  ensureDriverAssignedToTrip,
} = require('../services/routeContext.service');

const router = express.Router();

const buildRoutePathSnapshot = (route) => {
  const coordinates = Array.isArray(route?.path?.coordinates)
    ? route.path.coordinates
    : [];

  if (coordinates.length < 2) {
    return undefined;
  }

  return {
    type: 'LineString',
    coordinates: coordinates.map((entry) => [Number(entry[0]), Number(entry[1])]),
  };
};

router.get(
  '/active',
  authenticate,
  asyncHandler(async (_req, res) => {
    const activeTrips = await TripSession.find({ status: 'active' })
      .populate('jeepneyId driverId routeId')
      .sort({ startedAt: -1 });
    return ok(res, activeTrips, 'Active trips');
  })
);

router.get(
  '/mine',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const driver = await requireCurrentDriver(req.user);
    const trips = await TripSession.find({
      driverId: driver._id,
      status: { $in: ['scheduled', 'active'] },
    })
      .populate('jeepneyId driverId routeId')
      .sort({ createdAt: -1 });
    return ok(res, trips, 'Driver trips');
  })
);

router.post(
  '/',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    const payload = req.body || {};
    const startedAt = payload.status === 'active' ? new Date() : undefined;
    if (!payload.jeepneyId || !payload.routeId) {
      throw new ApiError(400, 'jeepneyId and routeId are required');
    }
    ensureObjectId(payload.jeepneyId, 'jeepneyId');
    ensureObjectId(payload.routeId, 'routeId');
    if (payload.status) {
      ensureEnum(payload.status, 'status', ['scheduled', 'active', 'completed', 'cancelled']);
    }
    const jeepney = await Jeepney.findById(payload.jeepneyId);
    if (!jeepney) {
      throw new ApiError(404, 'Jeepney not found');
    }
    if (jeepney.status !== 'active') {
      throw new ApiError(409, 'Jeepney is not active');
    }
    const route = await Route.findById(payload.routeId);
    if (!route) {
      throw new ApiError(404, 'Route not found');
    }
    if (route.status !== 'active') {
      throw new ApiError(409, 'Route is not active');
    }
    if (req.user.role === DRIVER) {
      const driver = await requireCurrentDriver(req.user);
      if (driver.status !== 'active') {
        throw new ApiError(403, 'Driver account must be active to create trips');
      }
      if (!driver.isVerified) {
        throw new ApiError(403, 'Driver must be verified before creating trips');
      }
      if (
        driver.assignedJeepneyId &&
        String(driver.assignedJeepneyId) !== String(jeepney._id)
      ) {
        throw new ApiError(403, 'This jeepney is not assigned to the driver');
      }
      payload.driverId = driver._id;
    } else {
      const requestedStatus = payload.status || 'scheduled';
      if (requestedStatus !== 'scheduled' && !payload.driverId) {
        throw new ApiError(400, 'driverId is required when creating a non-scheduled trip');
      }
    }
    const trip = await TripSession.create({
      ...payload,
      routePathSnapshot: buildRoutePathSnapshot(route),
      startedAt,
      active: payload.status === 'active',
    });
    return ok(res, trip, 'Trip session created', 201);
  })
);

router.patch(
  '/:id/start',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'trip id');
    const trip = await requireTrip(req.params.id);
    if (trip.status === 'active') {
      throw new ApiError(409, 'Trip already active');
    }
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      throw new ApiError(409, 'Trip is already closed');
    }
    if (req.user.role === DRIVER) {
      const driver = await requireCurrentDriver(req.user);
      if (driver.status !== 'active') {
        throw new ApiError(403, 'Driver account must be active to start a trip');
      }
      if (!driver.isVerified) {
        throw new ApiError(403, 'Driver must be verified to start a trip');
      }
      if (
        driver.assignedJeepneyId &&
        String(driver.assignedJeepneyId) !== String(trip.jeepneyId)
      ) {
        throw new ApiError(403, 'This jeepney is not assigned to the driver');
      }
      if (!trip.driverId) {
        trip.driverId = driver._id;
      } else if (String(trip.driverId) !== String(driver._id)) {
        throw new ApiError(403, 'You are not assigned to this trip');
      }
    }
    trip.status = 'active';
    if (
      (!trip.routePathSnapshot || !Array.isArray(trip.routePathSnapshot.coordinates)) &&
      trip.routeId
    ) {
      const route = await Route.findById(trip.routeId);
      trip.routePathSnapshot = buildRoutePathSnapshot(route);
    }
    trip.startedAt = new Date();
    trip.active = true;
    trip.acceptRequests = true;
    await trip.save();
    return ok(res, trip, 'Trip started');
  })
);

router.patch(
  '/:id/end',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'trip id');
    const trip = await requireTrip(req.params.id);
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      throw new ApiError(409, 'Trip already closed');
    }
    if (req.user.role === DRIVER) {
      await ensureDriverAssignedToTrip(req.user, trip);
    }
    trip.status = 'completed';
    trip.endedAt = new Date();
    trip.active = false;
    trip.acceptRequests = false;
    await trip.save();
    return ok(res, trip, 'Trip ended');
  })
);

router.patch(
  '/:id/availability',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'trip id');
    const trip = await requireTrip(req.params.id);
    await ensureDriverAssignedToTrip(req.user, trip);
    trip.acceptRequests = Boolean(req.body.acceptRequests);
    await trip.save();
    return ok(res, trip, 'Trip availability updated');
  })
);

router.get(
  '/',
  authenticate,
  authorize(ADMIN, DRIVER),
  asyncHandler(async (_req, res) => {
    const trips = await TripSession.find().sort({ createdAt: -1 });
    return ok(res, trips, 'All trips');
  })
);


module.exports = router;
