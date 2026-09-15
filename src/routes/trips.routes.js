const terminalQueue = require('../services/terminalQueue.service');
const { assertVehicleAllowed } = require('../services/operatingRules.service');
const express = require('express');
const mongoose = require('mongoose');
const Driver = require('../models/driver');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const Jeepney = require('../models/jeepney');
const Route = require('../models/route');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { apiRateLimiters } = require('../middlewares/rateLimits');
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
const {
  calculatePassengerEta,
} = require('../services/passengerEta.service');
const {
  invalidateDriverActiveContext,
} = require('../services/activeDriverContext.service');
const { redisKey } = require('../services/redis.service');
const { getOrLoadCachedRead } = require('../services/readCache.service');
const { emitOperationsChanged } = require('../realtime/socketServer');

const tripLifecycle = require('../services/tripLifecycle.service');
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
  asyncHandler(async (req, res) => {
    const filter = { status: 'active' };
    if (req.query.routeId != null && req.query.routeId !== '') {
      ensureObjectId(req.query.routeId, 'routeId');
      filter.routeId = req.query.routeId;
    }
    const cacheKey = redisKey(
      'read',
      'active-trips',
      filter.routeId || 'all'
    );
    const activeTrips = await getOrLoadCachedRead({
      key: cacheKey,
      ttlSeconds: 2,
      loader: () =>
        TripSession.find(filter)
          .select('-__v')
          .populate(
            'jeepneyId',
            'plateNumber jeepneyName vehicleTag capacity status lastKnownLocation lastSeenAt'
          )
          .populate('driverId', 'userId status licenseNumber employeeNumber')
          .populate('routeId', 'name code direction status')
          .sort({ startedAt: -1 })
          .lean(),
    });
    return ok(res, await Promise.all(activeTrips.value.map(terminalQueue.describe)), 'Active trips');
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
    return ok(res, await Promise.all(trips.map(terminalQueue.describe)), 'Driver trips');
  })
);

router.post(
  '/:id/passenger-eta',
  authenticate,
  authorize(PASSENGER),
  apiRateLimiters.eta,
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'trip id');
    const eta = await calculatePassengerEta({
      tripId: req.params.id,
      destination: req.body?.destination,
    });
    return ok(res, eta, 'Passenger traffic ETA');
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
    if (payload.status === 'active') await assertVehicleAllowed(jeepney);
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
    if (operatingMode === 'terminal_queue') {
      const terminal = resolveRouteTerminalStop(route);
      const document = { jeepneyId: jeepney._id, driverId: payload.driverId, routeId: route._id,
        routePathSnapshot: buildRoutePathSnapshot(route), terminalStopRef: terminal.stopRef, terminalLocation: terminal.location };
      const queued = await terminalQueue.checkIn({ document, actor: req.user, requestId: payload.requestId, reason: payload.reason });
      return ok(res, queued, 'Terminal check-in complete', 201);
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
    await invalidateDriverActiveContext(trip.driverId);
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
    if (trip.operatingMode === 'terminal_queue') {
      const terminalRoute = await Route.findById(trip.routeId);
      const terminal = resolveRouteTerminalStop(terminalRoute);
      if (!terminal) throw new ApiError(409, 'Terminal is unavailable');
      const queued = await terminalQueue.checkIn({ existingId: trip._id, actor: req.user,
        requestId: req.body.requestId, reason: req.body.reason, document: { driverId: trip.driverId, jeepneyId: trip.jeepneyId, routeId: trip.routeId,
          terminalStopRef: terminal.stopRef, terminalLocation: terminal.location, routePathSnapshot: buildRoutePathSnapshot(terminalRoute) } });
      return ok(res, queued, 'Terminal check-in complete');
    }
    await assertVehicleAllowed(await Jeepney.findById(trip.jeepneyId));
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
    await invalidateDriverActiveContext(trip.driverId);
    return ok(res, trip, 'Trip started');
  })
);

router.patch('/:id/terminal/:action', authenticate, authorize(DRIVER, ADMIN), asyncHandler(async (req, res) => {
  ensureObjectId(req.params.id, 'trip id');
  const trip = await terminalQueue.change({ tripId: req.params.id, actor: req.user, action: req.params.action,
    requestId: req.body.requestId, reason: req.body.reason });
  return ok(res, trip, 'Terminal queue updated');
}));

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
    const closedTrip = await tripLifecycle.endTrip(trip._id, { actor: req.user, requestId: req.body.requestId, reason: req.body.reason });
    if (trip.driverId) {
      await syncDriverActiveTripState({
        driverId: trip.driverId,
        trip: { operatingMode: 'route', terminalQueueStatus: 'off_queue' },
      });
    }
    await invalidateDriverActiveContext(trip.driverId);
    return ok(res, closedTrip, 'Trip ended');
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
    if (typeof req.body.acceptRequests !== 'boolean') throw new ApiError(400, 'acceptRequests must be a boolean');
    const updated = await tripLifecycle.setAvailability(trip._id, req.body.acceptRequests);
    return ok(res, updated, 'Trip availability updated');
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

    const delta = req.body?.delta;
    const operationId = req.body?.operationId;
    const isAdjustment = delta !== undefined;
    let requestedManualOccupancy = Number(req.body?.manualOccupancyCount);
    if (isAdjustment && (![-1, 1].includes(delta) ||
        typeof operationId !== 'string' || !/^[a-zA-Z0-9_-]{16,100}$/.test(operationId) ||
        req.body.manualOccupancyCount !== undefined)) {
      throw new ApiError(400, 'A +1 or -1 delta and a unique operationId are required');
    }
    if (!isAdjustment && (!Number.isInteger(requestedManualOccupancy) || requestedManualOccupancy < 0)) {
      throw new ApiError(
        400,
        'manualOccupancyCount must be a whole number at or above zero'
      );
    }

    let capacity = null;
    let nextOccupancyCount = 0;
    const occupancySession = await mongoose.startSession();
    try {
      await occupancySession.withTransaction(async () => {
        const freshTrip = await TripSession.findOne({
          _id: trip._id,
          status: 'active',
        }).session(occupancySession);
        if (!freshTrip) {
          throw new ApiError(409, 'Only active trips can update occupancy');
        }
        if (String(freshTrip.driverId) !== String(trip.driverId)) {
          throw new ApiError(403, 'Driver is no longer assigned to this trip');
        }
        const Operation = require('../models/occupancyOperation');
        if (isAdjustment) {
          const receipt = await Operation.findById(operationId).session(occupancySession);
          if (receipt) {
            if (String(receipt.tripId) !== String(trip._id) ||
                String(receipt.driverId) !== String(freshTrip.driverId) || receipt.delta !== delta) {
              throw new ApiError(409, 'Operation ID was already used for another adjustment');
            }
            return;
          }
          requestedManualOccupancy = (freshTrip.manualOccupancyCount || 0) + delta;
          if (requestedManualOccupancy < 0) throw new ApiError(409, 'Manual passenger count is already zero');
        } else if (req.body.expectedManualOccupancyCount !== freshTrip.manualOccupancyCount) {
          throw new ApiError(409, 'Passenger count changed; refresh before updating');
        }

        const jeepney = await Jeepney.findById(freshTrip.jeepneyId)
          .select('capacity status plateNumber jeepneyName vehicleTag')
          .session(occupancySession);
        if (!jeepney) {
          throw new ApiError(404, 'Jeepney not found');
        }

        capacity = Number(jeepney.capacity);
        const onboardRideCount = await RideSession.countDocuments({
          tripSessionId: freshTrip._id,
          status: 'onboard',
        }).session(occupancySession);
        nextOccupancyCount = onboardRideCount + requestedManualOccupancy;
        const reserved = freshTrip.operatingMode === 'terminal_queue' ? await require('../models/pickupRequest').countDocuments({ tripSessionId: freshTrip._id, status: { $in: ['pending', 'acknowledged'] }, expiresAt: { $gt: new Date() } }).session(occupancySession) : 0;
        if (nextOccupancyCount + reserved > capacity) throw new ApiError(409, 'Occupancy would consume reserved seats');
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

        freshTrip.manualOccupancyCount = requestedManualOccupancy;
        freshTrip.occupancyCount = nextOccupancyCount;
        if (
          Number.isFinite(capacity) &&
          capacity > 0 &&
          nextOccupancyCount >= capacity && freshTrip.operatingMode !== 'terminal_queue'
        ) {
          freshTrip.acceptRequests = false;
        }
        await freshTrip.save({ session: occupancySession });
        if (isAdjustment) await Operation.create([{
          _id: operationId, tripId: freshTrip._id, driverId: freshTrip.driverId, delta,
        }], { session: occupancySession });
      });
    } finally {
      await occupancySession.endSession();
    }

    const populatedTrip = await TripSession.findById(trip._id)
      .populate('jeepneyId driverId routeId');

    const occupancyEvent = {
      type: 'trip.occupancy.updated',
      tripId: trip._id.toString(),
      routeId: trip.routeId?.toString?.() || populatedTrip?.routeId?._id?.toString?.() || '',
      manualOccupancyCount: populatedTrip?.manualOccupancyCount ?? requestedManualOccupancy,
      occupancyCount: populatedTrip?.occupancyCount ?? nextOccupancyCount,
      capacity: Number.isFinite(capacity) ? capacity : null,
      acceptRequests: Boolean(populatedTrip?.acceptRequests),
      occurredAt: new Date().toISOString(),
    };

    const recipients = new Set();
    const driverUserId = populatedTrip?.driverId?.userId;
    if (driverUserId) recipients.add(driverUserId.toString());
    for (const userId of recipients) {
      emitOperationsChanged({ ...occupancyEvent, userId });
    }
    emitOperationsChanged({ ...occupancyEvent, role: 'passenger' });

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
