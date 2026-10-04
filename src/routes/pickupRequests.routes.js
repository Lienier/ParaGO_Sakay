const { createTripRecord } = require('../services/tripLifecycle.service');
const express = require('express');
const { requireBookingPoint } = require('../utils/bookingLocation');
const axios = require('axios');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const Route = require('../models/route');
const { publishNotification } = require('../services/notificationPublisher');
const { emitToTrip } = require('../realtime/socketServer');
const {
  isPointAfterOnRoute,
  isRoutePickupNearRoad,
  resolveRouteFareSnapshot,
} = require('../utils/routeGeo');
const { haversineMeters } = require('../utils/geo');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { DRIVER_ERROR_CODES, driverError } = require('../utils/driverError');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const {
  pickupRequestTtlMinutes,
  maxRequestsPerPassengerPerTrip,
  pickupRoadProximityMeters,
  unloadRoadProximityMeters,
  tomtomApiKey,
  jeepPassByReassignMeters,
} = require('../config/env');
const { ensureObjectId, ensureLatLng } = require('../utils/validators');
const {
  serializePickupRequest,
} = require('../utils/realtimePayloads');
const {
  requireCurrentDriver,
  requireCurrentPassenger,
  requireTrip,
  requirePickupRequest,
  ensureDriverAssignedToTrip,
  ensurePassengerOwnsPickupRequest,
} = require('../services/routeContext.service');
const { checkAndReassignPassedRequests } = require('../services/pickupReassignment.service');
const {
  canDriverAcknowledgePickupRequest,
  canPassengerCancelPickupRequest,
} = require('../services/pickupFlow.service');
const {
  compareTerminalQueueTrips,
  isTerminalPickupType,
  normalizeTerminalQueueStatus,
  normalizePickupType,
  resolveRouteTerminalStop,
} = require('../services/hybridDispatch.service');

const router = express.Router();
router.post('/:id/group-ready', authenticate, authorize(PASSENGER), asyncHandler(async (req, res) => {
  ensureObjectId(req.params.id, 'booking');
  return ok(res, await require('../services/groupBoarding.service').ready(req.params.id, req.user._id), 'Waiting for the driver to confirm your group count');
}));
router.post('/:id/group-board', authenticate, authorize(DRIVER), asyncHandler(async (req, res) => {
  ensureObjectId(req.params.id, 'booking');
  const booking = await requirePickupRequest(req.params.id);
  if ((booking.partySize ?? 1) <= 1) throw new ApiError(409, 'Use normal boarding for a solo booking.');
  const trip = await requireTrip(booking.tripSessionId);
  await ensureDriverAssignedToTrip(req.user, trip);
  const ride = await require('../services/boarding.service').completeBoardingForPickupRequest({
    pickupRequest: booking, trip, passengerId: booking.passengerId, boardingMethod: 'manual', allowExisting: true,
    groupConfirmation: { driverUserId: req.user._id, count: req.body.count, requestId: req.body.requestId },
  });
  return ok(res, ride, 'Group boarding confirmed');
}));
router.get('/capabilities', authenticate, authorize(PASSENGER), (_req, res) => {
  res.set('Cache-Control', 'no-store');
  return ok(res, { groupBookingsEnabled: require('../config/env').groupBookingsEnabled }, 'Booking capabilities');
});

const isFinitePositiveNumber = (value) =>
  Number.isFinite(Number(value)) && Number(value) > 0;
const normalizeStatus = (value) => String(value || '').trim().toLowerCase();

const pointCoordinates = (value) =>
  Array.isArray(value?.coordinates) && value.coordinates.length >= 2
    ? [Number(value.coordinates[0]), Number(value.coordinates[1])]
    : null;

const resolveRefId = (value) => {
  if (!value) return null;
  if (typeof value === 'string') return value;
  if (value._id) return value._id.toString();
  if (typeof value.toString === 'function') {
    const stringValue = value.toString();
    if (stringValue && stringValue !== '[object Object]') {
      return stringValue;
    }
  }
  return null;
};

const resolveTripDriverUserId = async (trip) => {
  const directUserId = resolveRefId(trip?.driverId?.userId);
  if (directUserId) {
    return directUserId;
  }

  const driverId = resolveRefId(trip?.driverId);
  if (!driverId) {
    return null;
  }

  const driver = await Driver.findById(driverId).select('userId');
  return resolveRefId(driver?.userId);
};

const ensureDriverCanHandlePickup = ({ driver, trip, accountStatus }) => {
  if (!driver) {
    throw driverError(403, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
      'Your driver profile is not available.', 'Sign in again or contact an administrator.');
  }
  if (normalizeStatus(accountStatus) !== 'active') {
    throw driverError(403, DRIVER_ERROR_CODES.ACCOUNT_INACTIVE,
      'Your driver account is not active.', 'Contact an administrator before handling pickups.');
  }
  if (driver.status !== 'active') {
    throw driverError(403, DRIVER_ERROR_CODES.DRIVER_OFFLINE,
      'Your driver status is offline.', 'Set your driver status to online and try again.');
  }
  if (!driver.assignedJeepneyId) {
    throw driverError(403, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
      'No jeepney is assigned to your driver account.', 'Contact an administrator before handling pickups.');
  }
  if (String(driver.assignedJeepneyId) !== String(trip.jeepneyId)) {
    throw driverError(403, DRIVER_ERROR_CODES.TRIP_NOT_ASSIGNED,
      'This trip uses a different jeepney assignment.', 'Refresh your trips and open the assigned jeepney.');
  }
};

const syncTerminalQueueStatus = async () => {};

const reverseGeocodeLabel = async ({ latitude, longitude }) => {
  if (!tomtomApiKey) {
    return null;
  }

  const response = await axios.get(
    `https://api.tomtom.com/search/2/reverseGeocode/${latitude},${longitude}.json`,
    {
      params: {
        key: tomtomApiKey,
        language: 'en-US',
      },
      timeout: 15000,
      headers: {
        Accept: 'application/json',
      },
    }
  );

  const addresses = Array.isArray(response.data?.addresses)
    ? response.data.addresses
    : [];
  const first = addresses[0];
  const address = first?.address || {};
  return (
    address.freeformAddress ||
    address.streetNameAndNumber ||
    address.streetName ||
    address.municipality ||
    null
  );
};

const resolveEligibleTripForRoute = async ({
  routeId,
  pickupLocation,
  pickupType,
  excludeTripIds = [],
  partySize = 1,
}) => {
  const normalizedPickupType = normalizePickupType(pickupType);
  const terminalUnavailable = () => new ApiError(
    409,
    'No jeepney is loading at this terminal right now. Choose roadside pickup or try again when a jeep is loading.',
    [],
    'TERMINAL_LOADING_UNAVAILABLE'
  );
  const trips = await TripSession.find({
    routeId,
    status: 'active',
    acceptRequests: true,
    ...(excludeTripIds.length > 0 ? { _id: { $nin: excludeTripIds } } : {}),
  })
    .populate({
      path: 'driverId',
      select: 'userId status',
      populate: {
        path: 'userId',
        select: 'status',
      },
    })
    .populate('jeepneyId', 'capacity status lastKnownLocation plateNumber jeepneyName')
    .sort({ startedAt: -1, createdAt: -1 });

  if (!trips.length) {
    if (normalizedPickupType === 'terminal') throw terminalUnavailable();
    throw new ApiError(409, 'No active jeepneys are available on this route right now', [], 'NO_ACTIVE_JEEPNEY');
  }

  const pickupCoordinates = pointCoordinates(pickupLocation);
  const eligibleTrips = [];

  for (const trip of trips) {
    const driver = trip.driverId;
    const jeepney = trip.jeepneyId;
    const tripOperatingMode = String(trip.operatingMode || 'route');
    if (
      !driver ||
      !driver.userId ||
      normalizeStatus(driver.userId.status) !== 'active' ||
      driver.status !== 'active'
    ) {
      continue;
    }
    if (!jeepney || jeepney.status !== 'active' || !isFinitePositiveNumber(jeepney.capacity)) {
      continue;
    }
    if (normalizedPickupType === 'terminal' && tripOperatingMode !== 'terminal_queue') {
      continue;
    }
    if (
      normalizedPickupType === 'terminal' &&
      normalizeTerminalQueueStatus(trip.terminalQueueStatus, {
        operatingMode: tripOperatingMode,
      }) !== 'loading'
    ) {
      continue;
    }
    if (normalizedPickupType === 'roadside' && tripOperatingMode === 'terminal_queue') {
      continue;
    }

    const seats = await require('../services/seatAccounting.service').counts(trip);
    const reservedSeats = seats.occupied + seats.reserved;
    const availableSeats = Number(jeepney.capacity) - reservedSeats;
    if (availableSeats < partySize) {
      continue;
    }

    const jeepneyCoordinates = pointCoordinates(jeepney.lastKnownLocation);
    const distanceMeters =
      normalizedPickupType === 'terminal'
        ? 0
        : pickupCoordinates && jeepneyCoordinates
        ? haversineMeters(
            pickupCoordinates[1],
            pickupCoordinates[0],
            jeepneyCoordinates[1],
            jeepneyCoordinates[0]
          )
        : Number.POSITIVE_INFINITY;

    eligibleTrips.push({
      trip,
      distanceMeters,
      availableSeats,
    });
  }

  if (!eligibleTrips.length) {
    if (normalizedPickupType === 'terminal') throw terminalUnavailable();
    throw new ApiError(
      409,
      'No nearby jeepney on this route has enough remaining capacity for a new booking',
      [],
      'INSUFFICIENT_SEATS'
    );
  }

  eligibleTrips.sort((left, right) => {
    if (normalizedPickupType === 'terminal') {
      return compareTerminalQueueTrips(left.trip, right.trip);
    }
    if (left.distanceMeters !== right.distanceMeters) {
      return left.distanceMeters - right.distanceMeters;
    }
    if (left.availableSeats !== right.availableSeats) {
      return right.availableSeats - left.availableSeats;
    }
    return 0;
  });

  return eligibleTrips[0].trip;
};

router.post(
  '/',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const payload = req.body || {};
    const partySize = require('../services/seatAccounting.service').partySize(payload.partySize);
    if (partySize > 1 && !require('../config/env').groupBookingsEnabled) {
      throw new ApiError(409, 'Companion bookings are not available yet. Book for yourself only.', [], 'GROUP_BOOKINGS_DISABLED');
    }
    const passenger = await requireCurrentPassenger(req.user, {
      notFoundMessage: 'Passenger profile not found',
    });

    // Check and expire any requests where jeep has passed by
    await checkAndReassignPassedRequests();

    if (!payload.routeId) {
      throw new ApiError(400, 'routeId is required');
    }
    ensureObjectId(payload.routeId, 'routeId');
    const route = await Route.findById(payload.routeId);
    if (!route) throw new ApiError(404, 'Route not found');
    const pickupType = normalizePickupType(payload.pickupType);
    const terminalStop = isTerminalPickupType(pickupType)
      ? resolveRouteTerminalStop(route)
      : null;
    if (isTerminalPickupType(pickupType) && !terminalStop) throw new ApiError(409, 'This route has no terminal configured. Choose roadside pickup or contact support.', [], 'TERMINAL_UNAVAILABLE');

    let pickupLocation = isTerminalPickupType(pickupType)
      ? terminalStop?.location
      : payload.pickupLocation;
    if (!pickupLocation || !Array.isArray(pickupLocation.coordinates) || pickupLocation.coordinates.length < 2) {
      throw new ApiError(400, 'Choose a pickup point on the selected route.', [], 'PICKUP_REQUIRED');
    }
    const [lngPickup, latPickup] = pickupLocation.coordinates;
    pickupLocation = requireBookingPoint(pickupLocation, 'pickup');
    ensureLatLng(latPickup, lngPickup, 'pickupLocation');

    if (isTerminalPickupType(pickupType)) {
      if (!terminalStop) {
        throw new ApiError(409, 'Selected route has no terminal stop configured');
      }
    } else if (!isRoutePickupNearRoad({
      latitude: latPickup,
      longitude: lngPickup,
      route,
      maxDistanceMeters: pickupRoadProximityMeters,
    })) {
      throw new ApiError(400, 'Move your pickup pin closer to the selected route.', [], 'PICKUP_OFF_ROUTE');
    }

    let destinationLocation = payload.destinationLocation;
    if (
      !destinationLocation ||
      !Array.isArray(destinationLocation.coordinates) ||
      destinationLocation.coordinates.length < 2
    ) {
      throw new ApiError(400, 'Choose an unload point on the selected route.', [], 'DESTINATION_REQUIRED');
    }
    const [lngDestination, latDestination] = destinationLocation.coordinates;
    destinationLocation = requireBookingPoint(destinationLocation, 'unload');
    ensureLatLng(latDestination, lngDestination, 'destinationLocation');

    if (!isRoutePickupNearRoad({
      latitude: latDestination,
      longitude: lngDestination,
      route,
      maxDistanceMeters: unloadRoadProximityMeters,
    })) {
      throw new ApiError(
        400,
        `Move your unload pin within ${unloadRoadProximityMeters} meters of the route.`, [], 'DESTINATION_OFF_ROUTE'
      );
    }
    if (!isPointAfterOnRoute({
      route,
      startLatitude: latPickup,
      startLongitude: lngPickup,
      endLatitude: latDestination,
      endLongitude: lngDestination,
    })) {
      throw new ApiError(
        400,
        'Choose an unload point after your pickup along the selected direction.', [], 'DESTINATION_BEFORE_PICKUP'
      );
    }

    const normalizedDestinationStopRef = String(
      payload.destinationStopRef || ''
    ).trim();
    if (!normalizedDestinationStopRef) {
      throw new ApiError(400, 'destinationStopRef is required');
    }

    let trip;
    // Always use auto-assignment to find nearest available jeepney
    trip = await resolveEligibleTripForRoute({
      routeId: route._id,
      pickupLocation,
      pickupType,
      partySize,
    });

    const pendingCount = await PickupRequest.countDocuments({
      tripSessionId: trip._id,
      passengerId: passenger._id,
      status: { $in: ['pending', 'acknowledged'] },
    });
    if (pendingCount >= maxRequestsPerPassengerPerTrip) {
      throw new ApiError(409, 'Too many pending requests for this trip');
    }

    const request = await createTripRecord(PickupRequest, {
      partySize,
      fareSnapshot: resolveRouteFareSnapshot({
        route,
        pickupLocation,
        destinationLocation: {
          type: 'Point',
          coordinates: [Number(lngDestination), Number(latDestination)],
        },
      }),
      passengerId: passenger._id,
      tripSessionId: trip._id,
      routeId: payload.routeId,
      pickupType,
      stopRef: isTerminalPickupType(pickupType)
        ? terminalStop?.stopRef || payload.stopRef
        : payload.stopRef,
      pickupLocation,
      terminalStopRef: terminalStop?.stopRef,
      terminalLocation: terminalStop?.location,
      destinationStopRef: normalizedDestinationStopRef,
      destinationLocation: {
        type: 'Point',
        coordinates: [Number(lngDestination), Number(latDestination)],
      },
      sourceNote: payload.sourceNote,
      expiresAt: new Date(Date.now() + pickupRequestTtlMinutes * 60 * 1000),
    }, { accepting: true });

    const tripDriverUserId = await resolveTripDriverUserId(trip);
    await publishNotification({
      userId: tripDriverUserId,
      type: 'pickup_request_created',
      title: isTerminalPickupType(pickupType)
        ? 'New terminal boarding request'
        : 'New roadside pickup request',
      body:
        `${req.user.fullName || 'Passenger'} requested ` +
        `${(isTerminalPickupType(pickupType)
          ? terminalStop?.stopRef
          : payload.stopRef) || 'a pickup stop'} to ` +
        `${normalizedDestinationStopRef}`,
      payload: {
        requestId: request._id,
        tripSessionId: trip._id.toString(),
        routeId: route._id.toString(),
        request: serializePickupRequest(request),
      },
      category: 'trip',
    });
    emitToTrip(trip._id.toString(), 'pickup_request.updated', {
      action: 'created',
      tripId: trip._id.toString(),
      routeId: route._id.toString(),
      request: serializePickupRequest(request),
      createdAt: new Date().toISOString(),
    });

    return ok(
      res,
      request,
      isTerminalPickupType(pickupType)
        ? 'Terminal boarding request created'
        : 'Pickup request created',
      201
    );
  })
);

router.get(
  '/reverse-geocode',
  authenticate,
  authorize(PASSENGER, ADMIN),
  asyncHandler(async (req, res) => {
    const latitude = Number(req.query.lat);
    const longitude = Number(req.query.lng);
    ensureLatLng(latitude, longitude, 'location');

    const label = await reverseGeocodeLabel({ latitude, longitude });
    return ok(
      res,
      {
        label,
      },
      'Reverse geocode lookup'
    );
  })
);

router.get(
  '/mine',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await requireCurrentPassenger(req.user, {
      notFoundMessage: 'Passenger profile not found',
    });
    const list = await PickupRequest.find({ passengerId: passenger._id }).sort({ createdAt: -1 });
    return ok(res, list, 'Passenger pickup requests');
  })
);

router.get(
  '/trip/:tripSessionId',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.tripSessionId, 'tripSessionId');
    const trip = await requireTrip(req.params.tripSessionId);
    if (req.user.role === DRIVER) {
      await ensureDriverAssignedToTrip(req.user, trip, {
        forbiddenMessage: 'Driver not assigned to this trip',
      });
    }
    const list = await PickupRequest.find({ tripSessionId: req.params.tripSessionId }).sort({
      status: 1,
      createdAt: -1,
    });
    return ok(res, list, 'Trip pickup requests');
  })
);

router.patch(
  '/:id/acknowledge',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'pickup request id');
    const request = await requirePickupRequest(req.params.id);
    const trip = await requireTrip(request.tripSessionId);
    if (trip.status !== 'active') {
      throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'This trip is no longer active for pickup acknowledgement.', 'Refresh the trip status before trying again.');
    }
    let driver;
    if (req.user.role === DRIVER) {
      driver = await ensureDriverAssignedToTrip(req.user, trip, {
        forbiddenMessage: 'You are not assigned to this request',
      });
      ensureDriverCanHandlePickup({
        driver,
        trip,
        accountStatus: req.user.status,
      });
    }
    if (!trip.driverId) {
      throw driverError(409, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING,
        'This trip has no assigned driver.', 'Ask an administrator to assign a driver, then refresh.');
    }

    if (request.status === 'acknowledged') {
      return ok(res, request, 'Pickup request already acknowledged');
    }
    if (!canDriverAcknowledgePickupRequest(request.status)) {
      throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'Only a pending pickup request can be acknowledged.', 'Refresh the request to see its current status.');
    }
    if (request.expiresAt <= new Date()) throw driverError(409, DRIVER_ERROR_CODES.TRIP_ALREADY_CLOSED,
      'This pickup request has expired.', 'Refresh the request list; the passenger must send a new request.');
    const previousStatus = request.status;
    request.status = 'acknowledged';
    request.acknowledgedAt = new Date();
    if (req.user.role === DRIVER) {
      driver ??= await requireCurrentDriver(req.user);
      request.acknowledgedBy = driver?._id || null;
    }
    const acknowledged = await PickupRequest.findOneAndUpdate(
      { _id: request._id, status: 'pending', expiresAt: { $gt: new Date() } },
      { $set: { status: 'acknowledged', acknowledgedAt: request.acknowledgedAt,
        ...(request.acknowledgedBy ? { acknowledgedBy: request.acknowledgedBy } : {}) } },
      { new: true }
    );
    if (!acknowledged) {
      const current = await PickupRequest.findById(request._id);
      if (current?.status === 'acknowledged') return ok(res, current, 'Pickup request already acknowledged');
      throw new ApiError(409, 'Pickup request is no longer pending');
    }
    if (request.pickupType === 'terminal') {
      await syncTerminalQueueStatus(trip);
    }
    const passengerUser = await Passenger.findById(request.passengerId).select('userId');
    await publishNotification({
      userId: passengerUser?.userId,
      type: 'pickup_request_acknowledged',
      title: 'Pickup request acknowledged',
      body: `Your pickup request near ${request.stopRef || 'the selected stop'} has been acknowledged`,
      payload: {
        requestId: request._id,
        tripSessionId: trip._id.toString(),
        previousStatus,
        request: serializePickupRequest(request),
      },
      category: 'trip',
    }).catch(() => console.error('[Pickup] Acknowledgement notification failed after save'));
    return ok(res, request, 'Pickup request acknowledged');
  })
);

router.patch(
  '/:id/cancel',
  authenticate,
  authorize(PASSENGER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'pickup request id');
    const request = await requirePickupRequest(req.params.id);

    if (req.user.role === PASSENGER) {
      await ensurePassengerOwnsPickupRequest(req.user, request, {
        forbiddenMessage: 'You can only cancel your own request',
      });
    }
    if (!canPassengerCancelPickupRequest(request.status)) {
      throw new ApiError(409, 'Only pending or acknowledged requests can be cancelled');
    }

    const cancelled = await PickupRequest.findOneAndUpdate({
      _id: request._id, status: { $in: ['pending', 'acknowledged'] },
    }, { $set: { status: 'cancelled' } }, { new: true });
    if (!cancelled) throw new ApiError(409, 'Pickup request is no longer available for cancellation');
    request.status = cancelled.status;
    const trip = await TripSession.findById(request.tripSessionId)
      .populate('driverId', 'userId');
    if (request.pickupType === 'terminal') {
      await syncTerminalQueueStatus(trip);
    }
    await publishNotification({
      userId: await resolveTripDriverUserId(trip),
      type: 'pickup_request_cancelled',
      title: 'Pickup request cancelled',
      body: `Pickup request near ${request.stopRef || 'the selected stop'} was cancelled by the passenger.`,
      payload: {
        requestId: request._id.toString(),
        tripSessionId: request.tripSessionId?.toString() || '',
        request: serializePickupRequest(request),
      },
      category: 'trip',
    });
    emitToTrip(request.tripSessionId?.toString() || '', 'pickup_request.updated', {
      action: 'cancelled',
      tripId: request.tripSessionId?.toString() || '',
      routeId: request.routeId?.toString() || '',
      request: serializePickupRequest(request),
      createdAt: new Date().toISOString(),
    });
    return ok(res, request, 'Pickup request cancelled');
  })
);

router.patch(
  '/:id/complete',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'pickup request id');
    const request = await requirePickupRequest(req.params.id);
    const trip = await requireTrip(request.tripSessionId, {
      notFoundMessage: 'Trip not found for this request',
    });
    if (trip.status !== 'active') {
      throw new ApiError(409, 'Trip is not active for pickup confirmation');
    }
    if (req.user.role === DRIVER) {
      const driver = await ensureDriverAssignedToTrip(req.user, trip, {
        forbiddenMessage: 'You are not assigned to this request',
      });
      ensureDriverCanHandlePickup({
        driver,
        trip,
        accountStatus: req.user.status,
      });
    }
    const rideSession = await RideSession.findOne({
      pickupRequestId: request._id,
    });
    if (!rideSession) {
      throw new ApiError(
        409,
        'Passenger must validate boarding before pickup can be completed'
      );
    }
    if (rideSession.status !== 'onboard' && rideSession.status !== 'completed') {
      throw new ApiError(
        409,
        'Pickup can only be confirmed for an onboard or completed ride session'
      );
    }
    if (request.status !== 'completed') {
      request.status = 'completed';
      request.acknowledgedAt = request.acknowledgedAt || new Date();
      await request.save();
    }
    if (request.pickupType === 'terminal') {
      await syncTerminalQueueStatus(trip);
    }
    return ok(res, request, 'Pickup request marked completed');
  })
);

router.post('/:id/transfer/:decision', authenticate, authorize(PASSENGER), asyncHandler(async (req, res) => {
  ensureObjectId(req.params.id, 'request id');
  if (!['accept', 'decline'].includes(req.params.decision)) throw new ApiError(400, 'Invalid transfer decision');
  const passenger = await requireCurrentPassenger(req.user);
  const result = await require('../services/terminalQueue.service').transfer({ requestId: req.params.id,
    passengerId: passenger._id, offerId: req.body.offerId, accept: req.params.decision === 'accept' });
  return ok(res, result, 'Transfer updated');
}));

module.exports = router;
