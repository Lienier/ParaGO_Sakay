const express = require('express');
const Driver = require('../models/driver');
const RideSession = require('../models/rideSession');
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
const {
  nextTerminalQueueNumber,
  normalizeTerminalQueueStatus,
  normalizeTripOperatingMode,
  resolveRouteTerminalStop,
} = require('../services/hybridDispatch.service');

const router = express.Router();
const terminalQueueCreateRetryLimit = 4;
const normalizeStatus = (value) => String(value || '').trim().toLowerCase();

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

const isDuplicateKeyError = (error) => error?.code === 11000;

const buildTerminalQueueFields = async ({
  route,
  operatingMode,
  startedAt,
  excludeTripId,
}) => {
  if (operatingMode !== 'terminal_queue') {
    return {
      terminalQueueStatus: normalizeTerminalQueueStatus(undefined, {
        operatingMode,
      }),
      terminalQueueNumber: undefined,
      terminalCheckedInAt: undefined,
      terminalStopRef: undefined,
      terminalLocation: undefined,
    };
  }

  const terminalStop = resolveRouteTerminalStop(route);
  if (!terminalStop) {
    throw new ApiError(409, 'Selected route has no terminal stop configured');
  }

  const existingQueueTrips = await TripSession.find({
    routeId: route._id,
    operatingMode: 'terminal_queue',
    status: { $in: ['scheduled', 'active'] },
    ...(excludeTripId ? { _id: { $ne: excludeTripId } } : {}),
  }).select('terminalQueueNumber terminalCheckedInAt status createdAt startedAt');

  return {
    terminalQueueStatus: normalizeTerminalQueueStatus(undefined, {
      operatingMode,
    }),
    terminalQueueNumber: nextTerminalQueueNumber(existingQueueTrips),
    terminalCheckedInAt: startedAt || new Date(),
    terminalStopRef: terminalStop.stopRef,
    terminalLocation: terminalStop.location,
  };
};

const syncDriverActiveTripState = async ({ driverId, trip }) => {
  if (!driverId || !trip) {
    return;
  }

  const operatingMode = normalizeTripOperatingMode(trip.operatingMode);
  if (operatingMode !== 'terminal_queue') {
    await Driver.findByIdAndUpdate(driverId, {
      $set: {
        operatingMode: 'route',
        terminalQueueStatus: 'off_queue',
      },
      $unset: {
        terminalCheckedInAt: '',
        terminalQueueNumber: '',
        terminalStopRef: '',
      },
    });
    return;
  }

  await Driver.findByIdAndUpdate(driverId, {
    $set: {
      operatingMode,
      terminalQueueStatus: normalizeTerminalQueueStatus(
        trip.terminalQueueStatus,
        { operatingMode }
      ),
      terminalCheckedInAt: trip.terminalCheckedInAt || trip.startedAt || new Date(),
      terminalQueueNumber: trip.terminalQueueNumber,
      terminalStopRef: trip.terminalStopRef,
    },
  });
};

const createTripSession = async ({
  payload,
  route,
  operatingMode,
  startedAt,
}) => {
  for (let attempt = 0; attempt < terminalQueueCreateRetryLimit; attempt += 1) {
    const terminalFields = await buildTerminalQueueFields({
      route,
      operatingMode,
      startedAt,
    });

    try {
      return await TripSession.create({
        ...payload,
        routePathSnapshot: buildRoutePathSnapshot(route),
        startedAt,
        active: payload.status === 'active',
        operatingMode,
        ...terminalFields,
      });
    } catch (error) {
      const canRetry =
        operatingMode === 'terminal_queue' &&
        isDuplicateKeyError(error) &&
        attempt < terminalQueueCreateRetryLimit - 1;
      if (!canRetry) {
        throw error;
      }
    }
  }

  throw new ApiError(
    409,
    'Unable to reserve a unique terminal queue slot right now'
  );
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
    if (payload.driverId) {
      ensureObjectId(payload.driverId, 'driverId');
    }
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
    const operatingMode = normalizeTripOperatingMode(payload.operatingMode);
    if (
      operatingMode === 'terminal_queue' &&
      !resolveRouteTerminalStop(route)
    ) {
      throw new ApiError(409, 'Selected route has no terminal stop configured');
    }

    if (req.user.role === DRIVER) {
      const driver = await requireCurrentDriver(req.user);
      if (normalizeStatus(req.user.status) !== 'active') {
        throw new ApiError(403, 'Driver account must be active to create trips');
      }
      if (driver.status !== 'active') {
        throw new ApiError(403, 'Driver must be online to create trips');
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
    const trip = await createTripSession({
      payload,
      route,
      operatingMode,
      startedAt,
    });
    if (trip.status === 'active' && trip.driverId) {
      await syncDriverActiveTripState({ driverId: trip.driverId, trip });
    }
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
    let route;
    if (trip.status === 'active') {
      throw new ApiError(409, 'Trip already active');
    }
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      throw new ApiError(409, 'Trip is already closed');
    }
    if (req.user.role === DRIVER) {
      const driver = await requireCurrentDriver(req.user);
      if (normalizeStatus(req.user.status) !== 'active') {
        throw new ApiError(403, 'Driver account must be active to start a trip');
      }
      if (driver.status !== 'active') {
        throw new ApiError(403, 'Driver must be online to start a trip');
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
      route = await Route.findById(trip.routeId);
      trip.routePathSnapshot = buildRoutePathSnapshot(route);
    }
    trip.startedAt = new Date();
    trip.active = true;
    trip.acceptRequests = true;
    trip.operatingMode = normalizeTripOperatingMode(trip.operatingMode);
    if (trip.operatingMode === 'terminal_queue') {
      route = route || (trip.routeId ? await Route.findById(trip.routeId) : null);
      if (!route) {
        throw new ApiError(409, 'Route is required for a terminal queue trip');
      }
      const terminalFields = await buildTerminalQueueFields({
        route,
        operatingMode: trip.operatingMode,
        startedAt: trip.startedAt,
        excludeTripId: trip._id,
      });
      trip.terminalQueueStatus = normalizeTerminalQueueStatus(
        trip.terminalQueueStatus,
        { operatingMode: trip.operatingMode }
      );
      trip.terminalQueueNumber =
        trip.terminalQueueNumber || terminalFields.terminalQueueNumber;
      trip.terminalCheckedInAt =
        trip.terminalCheckedInAt || terminalFields.terminalCheckedInAt;
      trip.terminalStopRef = trip.terminalStopRef || terminalFields.terminalStopRef;
      trip.terminalLocation = trip.terminalLocation || terminalFields.terminalLocation;
    } else {
      trip.terminalQueueStatus = normalizeTerminalQueueStatus(
        trip.terminalQueueStatus,
        { operatingMode: trip.operatingMode }
      );
      trip.terminalCheckedInAt = undefined;
      trip.terminalQueueNumber = undefined;
      trip.terminalStopRef = undefined;
      trip.terminalLocation = undefined;
    }
    await trip.save();
    if (trip.driverId) {
      await syncDriverActiveTripState({ driverId: trip.driverId, trip });
    }
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
    if (trip.operatingMode === 'terminal_queue') {
      trip.terminalQueueStatus = 'departed';
    }
    await trip.save();
    if (trip.driverId) {
      await syncDriverActiveTripState({
        driverId: trip.driverId,
        trip: { operatingMode: 'route', terminalQueueStatus: 'off_queue' },
      });
    }
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

router.patch(
  '/:id/occupancy',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'trip id');
    const trip = await requireTrip(req.params.id);
    await ensureDriverAssignedToTrip(req.user, trip);

    if (trip.status !== 'active') {
      throw new ApiError(409, 'Only active trips can update occupancy');
    }

    const requestedManualOccupancy = Number(req.body?.manualOccupancyCount);
    if (!Number.isInteger(requestedManualOccupancy) || requestedManualOccupancy < 0) {
      throw new ApiError(
        400,
        'manualOccupancyCount must be a whole number at or above zero'
      );
    }

    const jeepney = await Jeepney.findById(trip.jeepneyId).select(
      'capacity status plateNumber jeepneyName vehicleTag'
    );
    if (!jeepney) {
      throw new ApiError(404, 'Jeepney not found');
    }

    const capacity = Number(jeepney.capacity);
    const onboardRideCount = await RideSession.countDocuments({
      tripSessionId: trip._id,
      status: 'onboard',
    });
    const nextOccupancyCount = onboardRideCount + requestedManualOccupancy;
    if (
      Number.isFinite(capacity) &&
      capacity > 0 &&
      nextOccupancyCount > capacity
    ) {
      throw new ApiError(
        409,
        `Occupancy cannot exceed jeepney capacity of ${capacity}`
      );
    }

    trip.manualOccupancyCount = requestedManualOccupancy;
    trip.occupancyCount = nextOccupancyCount;
    if (
      Number.isFinite(capacity) &&
      capacity > 0 &&
      nextOccupancyCount >= capacity
    ) {
      trip.acceptRequests = false;
    }
    await trip.save();

    const populatedTrip = await TripSession.findById(trip._id)
      .populate('jeepneyId driverId routeId');

    return ok(res, populatedTrip || trip, 'Trip occupancy updated');
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
