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
const { DRIVER_ERROR_CODES, driverError } = require('../utils/driverError');
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
    throw driverError(409, DRIVER_ERROR_CODES.TERMINAL_NOT_CONFIGURED,
      'This route has no configured departure terminal.', 'Choose a route with a terminal before starting a trip.');
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
        flowVersion: require('../config/env').automaticGroupFlowEnabled ? 2 : 1,
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

  throw driverError(409, DRIVER_ERROR_CODES.QUEUE_CONFLICT,
    'The terminal queue is busy and could not reserve a position.', 'Refresh the queue and try again.');
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
      throw driverError(400, 'TRIP_FIELDS_REQUIRED', 'A jeepney and route are required.', 'Select both before starting terminal entry.');
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
      throw driverError(404, DRIVER_ERROR_CODES.JEEPNEY_NOT_FOUND, 'The selected jeepney was not found.', 'Refresh your assigned jeepney and try again.');
    }
    if (jeepney.status !== 'active') {
      throw driverError(409, DRIVER_ERROR_CODES.JEEPNEY_INACTIVE, 'The selected jeepney is not active.', 'Ask an administrator to activate the jeepney before starting.');
    }
    const route = await Route.findById(payload.routeId);
    if (!route) {
      throw driverError(404, DRIVER_ERROR_CODES.ROUTE_NOT_FOUND, 'The selected route was not found.', 'Refresh the route list and choose an active route.');
    }
    if (route.status !== 'active') {
      throw driverError(409, DRIVER_ERROR_CODES.ROUTE_INACTIVE, 'The selected route is not active.', 'Choose an active route or contact an administrator.');
    }
    const requestedOperatingMode = String(payload.operatingMode || '').trim().toLowerCase();
    if (requestedOperatingMode === 'route') {
      throw driverError(409, 'DIRECT_ROUTE_NOT_ALLOWED',
        'A trip must begin at its configured terminal.', 'Start terminal entry and complete terminal departure before driving the route.');
    }
    const operatingMode = 'terminal_queue';
    if (
      operatingMode === 'terminal_queue' &&
      !resolveRouteTerminalStop(route)
    ) {
      throw driverError(409, DRIVER_ERROR_CODES.TERMINAL_NOT_CONFIGURED,
        'This route has no configured departure terminal.', 'Choose a route with a terminal before starting a trip.');
    }

    if (req.user.role === DRIVER) {
      const driver = await requireCurrentDriver(req.user);
      if (normalizeStatus(req.user.status) !== 'active') {
        throw driverError(403, DRIVER_ERROR_CODES.ACCOUNT_INACTIVE,
          'Your driver account is not active.', 'Contact an administrator before starting a trip.');
      }
      if (driver.status !== 'active') {
        throw driverError(403, DRIVER_ERROR_CODES.DRIVER_OFFLINE,
          'Your driver status is offline.', 'Set your driver status to online and try again.');
      }
      if (
        driver.assignedJeepneyId &&
        String(driver.assignedJeepneyId) !== String(jeepney._id)
        ) {
        throw driverError(403, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
          'This jeepney is not assigned to your driver account.', 'Use your assigned jeepney or contact an administrator.');
      }
      payload.driverId = driver._id;
    } else {
      const requestedStatus = payload.status || 'scheduled';
      if (requestedStatus !== 'scheduled' && !payload.driverId) {
      throw driverError(400, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
        'A driver assignment is required for a trip that starts immediately.', 'Assign a driver or create a scheduled terminal trip.');
      }
    }
    if (operatingMode === 'terminal_queue') {
      if (!payload.driverId) throw driverError(400, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
        'A driver assignment is required for terminal entry.', 'Select an assigned driver before creating the terminal trip.');
      const intent = await require('../services/terminalIntent.service').createTerminalIntent({
        driverId: payload.driverId, routeId: route._id, jeepneyId: jeepney._id,
      });
      return ok(res, await terminalQueue.describe(intent),
        intent.status === 'scheduled' ? 'Drive to the configured terminal; arrival will be detected automatically' : 'Existing trip retained', 201);
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
      throw driverError(409, 'TRIP_ALREADY_ACTIVE', 'This trip is already active.', 'Refresh the trip status and continue from the active trip.');
    }
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      throw driverError(409, DRIVER_ERROR_CODES.TRIP_ALREADY_CLOSED, 'This trip has already ended.', 'Refresh your trip list before starting another trip.');
    }
    if (req.user.role === DRIVER) {
      const driver = await requireCurrentDriver(req.user);
      if (normalizeStatus(req.user.status) !== 'active') {
        throw driverError(403, DRIVER_ERROR_CODES.ACCOUNT_INACTIVE,
          'Your driver account is not active.', 'Contact an administrator before starting a trip.');
      }
      if (driver.status !== 'active') {
        throw driverError(403, DRIVER_ERROR_CODES.DRIVER_OFFLINE,
          'Your driver status is offline.', 'Set your driver status to online and try again.');
      }
      if (
        driver.assignedJeepneyId &&
        String(driver.assignedJeepneyId) !== String(trip.jeepneyId)
      ) {
        throw driverError(403, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
          'This jeepney is not assigned to your driver account.', 'Use your assigned jeepney or contact an administrator.');
      }
      if (!trip.driverId) {
        trip.driverId = driver._id;
      } else if (String(trip.driverId) !== String(driver._id)) {
        throw driverError(403, DRIVER_ERROR_CODES.TRIP_NOT_ASSIGNED,
          'This trip is assigned to a different driver.', 'Open your assigned trip before continuing.');
      }
    }
    if (trip.operatingMode === 'terminal_queue') {
      if (trip.status === 'scheduled' && trip.terminalQueueStatus === 'off_queue') {
        throw driverError(409, DRIVER_ERROR_CODES.TERMINAL_ARRIVAL_PENDING,
          'Terminal arrival has not been confirmed by fresh GPS yet.', 'Drive to the configured terminal and keep fresh GPS enabled.');
      }
      throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'Terminal check-in is already being processed.', 'Wait for the next GPS update and refresh the trip status.');
    }
    await assertVehicleAllowed(await Jeepney.findById(trip.jeepneyId));
    trip.status = 'active';
    trip.flowVersion = require('../config/env').automaticGroupFlowEnabled ? 2 : 1;
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
        throw driverError(409, DRIVER_ERROR_CODES.ROUTE_NOT_FOUND,
          'A route is required for a terminal queue trip.', 'Select an active route and try again.');
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
  return ok(res, await terminalQueue.describe(trip), 'Terminal queue updated');
}));

router.patch(
  '/:id/end',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'trip id');
    const trip = await requireTrip(req.params.id);
    if (trip.status === 'completed' || trip.status === 'cancelled') {
      throw driverError(409, DRIVER_ERROR_CODES.TRIP_ALREADY_CLOSED, 'This trip has already ended.', 'Refresh your trip list.');
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
    return ok(res, await terminalQueue.describe(closedTrip), 'Trip ended');
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
    if (typeof req.body.acceptRequests !== 'boolean') throw driverError(400, 'INVALID_AVAILABILITY_VALUE',
      'Pickup availability must be enabled or paused.', 'Choose one of the available pickup controls.');
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
      throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'Passenger counts can only change on an active trip.', 'Refresh the trip status before changing the count.');
    }

    const delta = req.body?.delta;
    const operationId = req.body?.operationId;
    const isAdjustment = delta !== undefined;
    const supportedDeltas = new Set([-5, -3, -2, -1, 1, 2, 3, 5]);
    let requestedManualOccupancy = Number(req.body?.manualOccupancyCount);
    if (isAdjustment && (!Number.isInteger(delta) || !supportedDeltas.has(delta) ||
        typeof operationId !== 'string' || !/^[a-zA-Z0-9_-]{16,100}$/.test(operationId) ||
        req.body.manualOccupancyCount !== undefined)) {
      throw driverError(400, 'INVALID_OCCUPANCY_ADJUSTMENT',
        'Passenger count adjustment is invalid.', 'Use +1, +2, +3, +5, -1, -2, -3, or -5 with a new operation.');
    }
    if (!isAdjustment && (!Number.isInteger(requestedManualOccupancy) || requestedManualOccupancy < 0)) {
      throw driverError(400, 'INVALID_OCCUPANCY_COUNT',
        'Manual passenger count must be a whole number of zero or more.', 'Enter a valid passenger count and try again.');
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
          throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
            'Passenger counts can only change on an active trip.', 'Refresh the trip status before changing the count.');
        }
        if (String(freshTrip.driverId) !== String(trip.driverId)) {
          throw driverError(403, DRIVER_ERROR_CODES.TRIP_NOT_ASSIGNED,
            'Your driver account is no longer assigned to this trip.', 'Refresh your trips before changing the count.');
        }
        const Operation = require('../models/occupancyOperation');
        if (isAdjustment) {
          const receipt = await Operation.findById(operationId).session(occupancySession);
          if (receipt) {
            if (String(receipt.tripId) !== String(trip._id) ||
                String(receipt.driverId) !== String(freshTrip.driverId) || receipt.delta !== delta) {
              throw driverError(409, DRIVER_ERROR_CODES.DUPLICATE_OPERATION,
                'This passenger-count operation was already used for another change.', 'Refresh the count before trying again.');
            }
            return;
          }
          requestedManualOccupancy = (freshTrip.manualOccupancyCount || 0) + delta;
          if (requestedManualOccupancy < 0) throw driverError(409, 'OCCUPANCY_ALREADY_ZERO',
            'There are no manual passengers to remove.', 'Refresh the count and remove a smaller number.');
        } else if (req.body.expectedManualOccupancyCount !== freshTrip.manualOccupancyCount) {
          throw driverError(409, DRIVER_ERROR_CODES.STALE_OCCUPANCY,
            'The passenger count changed on another device.', 'Refresh the count before making another change.');
        }

        const jeepney = await Jeepney.findById(freshTrip.jeepneyId)
          .select('capacity status plateNumber jeepneyName vehicleTag')
          .session(occupancySession);
        if (!jeepney) {
          throw driverError(404, DRIVER_ERROR_CODES.JEEPNEY_NOT_FOUND,
            'The assigned jeepney could not be found.', 'Refresh your driver assignment.');
        }

        capacity = Number(jeepney.capacity);
        const seatCounts = await require('../services/seatAccounting.service').counts(freshTrip, occupancySession);
        const onboardRideCount = seatCounts.onboard;
        nextOccupancyCount = onboardRideCount + requestedManualOccupancy;
        const reserved = seatCounts.reserved;
        if (nextOccupancyCount + reserved > capacity) throw driverError(409, DRIVER_ERROR_CODES.CAPACITY_CONFLICT,
          'That change would use seats reserved for booked passengers.', 'Add fewer manual passengers or wait for reservations to resolve.');
        if (
          Number.isFinite(capacity) &&
          capacity > 0 &&
          nextOccupancyCount > capacity
        ) {
          throw driverError(409, DRIVER_ERROR_CODES.CAPACITY_CONFLICT,
            `Passenger count cannot exceed this jeepney's ${capacity}-seat capacity.`, 'Remove passengers or wait for a seat to become available.');
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
