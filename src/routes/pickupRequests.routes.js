const express = require('express');
const axios = require('axios');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const Route = require('../models/route');
const { publishNotification } = require('../services/notificationPublisher');
const {
  isPointAfterOnRoute,
  isRoutePickupNearRoad,
  pickDefaultRouteCoordinate,
  resolveRouteFareSnapshot,
} = require('../utils/routeGeo');
const { haversineMeters } = require('../utils/geo');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const {
  pickupRequestTtlMinutes,
  maxRequestsPerPassengerPerTrip,
  pickupRoadProximityMeters,
  pickupCurrentLocationMaxDistanceMeters,
  unloadRoadProximityMeters,
  tomtomApiKey,
} = require('../config/env');
const { ensureObjectId, ensureLatLng } = require('../utils/validators');
const {
  serializePickupRequest,
  serializeRideSession,
} = require('../utils/realtimePayloads');
const {
  requireCurrentDriver,
  requireCurrentPassenger,
  requireTrip,
  requirePickupRequest,
  ensureDriverAssignedToTrip,
  ensurePassengerOwnsPickupRequest,
} = require('../services/routeContext.service');

const router = express.Router();

const isFinitePositiveNumber = (value) =>
  Number.isFinite(Number(value)) && Number(value) > 0;

const pointCoordinates = (value) =>
  Array.isArray(value?.coordinates) && value.coordinates.length >= 2
    ? [Number(value.coordinates[0]), Number(value.coordinates[1])]
    : null;

const ensureDriverCanHandlePickup = ({ driver, trip }) => {
  if (!driver) {
    throw new ApiError(403, 'Driver profile missing');
  }
  if (driver.status !== 'active') {
    throw new ApiError(403, 'Driver account must be active to handle pickups');
  }
  if (!driver.isVerified) {
    throw new ApiError(403, 'Driver must be verified to handle pickups');
  }
  if (!driver.assignedJeepneyId) {
    throw new ApiError(403, 'Driver must be assigned to a jeepney before handling pickups');
  }
  if (String(driver.assignedJeepneyId) !== String(trip.jeepneyId)) {
    throw new ApiError(403, 'Focused trip must use the driver assigned jeepney');
  }
};

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
}) => {
  const trips = await TripSession.find({
    routeId,
    status: 'active',
    acceptRequests: true,
  })
    .populate('driverId', 'userId isVerified status')
    .populate('jeepneyId', 'capacity status lastKnownLocation plateNumber jeepneyName')
    .sort({ startedAt: -1, createdAt: -1 });

  if (!trips.length) {
    throw new ApiError(409, 'No active jeepneys are available on this route right now');
  }

  const pickupCoordinates = pointCoordinates(pickupLocation);
  const eligibleTrips = [];

  for (const trip of trips) {
    const driver = trip.driverId;
    const jeepney = trip.jeepneyId;
    if (!driver || !driver.userId || !driver.isVerified || driver.status !== 'active') {
      continue;
    }
    if (!jeepney || jeepney.status !== 'active' || !isFinitePositiveNumber(jeepney.capacity)) {
      continue;
    }

    const rideCount = await RideSession.countDocuments({
      tripSessionId: trip._id,
      status: { $in: ['waiting', 'onboard'] },
    });
    const pendingRequestCount = await PickupRequest.countDocuments({
      tripSessionId: trip._id,
      status: { $in: ['pending', 'acknowledged'] },
    });
    const occupiedSeats = Number.isFinite(Number(trip.occupancyCount))
      ? Number(trip.occupancyCount)
      : rideCount;
    const reservedSeats = Math.max(occupiedSeats, rideCount) + pendingRequestCount;
    const availableSeats = Number(jeepney.capacity) - reservedSeats;
    if (availableSeats < 1) {
      continue;
    }

    const jeepneyCoordinates = pointCoordinates(jeepney.lastKnownLocation);
    const distanceMeters =
      pickupCoordinates && jeepneyCoordinates
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
    throw new ApiError(
      409,
      'No nearby jeepney on this route has enough remaining capacity for a new booking'
    );
  }

  eligibleTrips.sort((left, right) => {
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
    const passenger = await requireCurrentPassenger(req.user, {
      notFoundMessage: 'Passenger profile not found',
    });

    if (!payload.routeId) {
      throw new ApiError(400, 'routeId is required');
    }
    ensureObjectId(payload.routeId, 'routeId');
    const route = await Route.findById(payload.routeId);
    if (!route) throw new ApiError(404, 'Route not found');

    let pickupLocation = payload.pickupLocation;
    if (!pickupLocation || !Array.isArray(pickupLocation.coordinates) || pickupLocation.coordinates.length < 2) {
      pickupLocation = pickDefaultRouteCoordinate(route);
      if (!pickupLocation) {
        throw new ApiError(400, 'pickupLocation is required for this route');
      }
    }
    const [lngPickup, latPickup] = pickupLocation.coordinates;
    ensureLatLng(latPickup, lngPickup, 'pickupLocation');

    if (
      !payload.currentLocation ||
      !Array.isArray(payload.currentLocation.coordinates) ||
      payload.currentLocation.coordinates.length < 2
    ) {
      throw new ApiError(400, 'currentLocation is required');
    }
    const [lngCurrent, latCurrent] = payload.currentLocation.coordinates;
    ensureLatLng(latCurrent, lngCurrent, 'currentLocation');
    const pickupDistanceFromPassenger = haversineMeters(
      latPickup,
      lngPickup,
      Number(latCurrent),
      Number(lngCurrent)
    );
    if (pickupDistanceFromPassenger > pickupCurrentLocationMaxDistanceMeters) {
      throw new ApiError(
        400,
        `Pickup point must stay within ${pickupCurrentLocationMaxDistanceMeters} meters of your current location`
      );
    }

    if (!isRoutePickupNearRoad({
      latitude: latPickup,
      longitude: lngPickup,
      route,
      maxDistanceMeters: pickupRoadProximityMeters,
    })) {
      throw new ApiError(400, 'Pickup point must be near the selected route');
    }

    let destinationLocation = payload.destinationLocation;
    if (
      !destinationLocation ||
      !Array.isArray(destinationLocation.coordinates) ||
      destinationLocation.coordinates.length < 2
    ) {
      throw new ApiError(400, 'destinationLocation is required');
    }
    const [lngDestination, latDestination] = destinationLocation.coordinates;
    ensureLatLng(latDestination, lngDestination, 'destinationLocation');

    if (!isRoutePickupNearRoad({
      latitude: latDestination,
      longitude: lngDestination,
      route,
      maxDistanceMeters: unloadRoadProximityMeters,
    })) {
      throw new ApiError(
        400,
        `Unload point must be within ${unloadRoadProximityMeters} meters of the route`
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
        'Unload point must come after the pickup point along the route'
      );
    }

    const normalizedDestinationStopRef = String(
      payload.destinationStopRef || ''
    ).trim();
    if (!normalizedDestinationStopRef) {
      throw new ApiError(400, 'destinationStopRef is required');
    }

    let trip;
    if (payload.tripSessionId) {
      ensureObjectId(payload.tripSessionId, 'tripSessionId');
      trip = await requireTrip(payload.tripSessionId, {
        populate: [
          { path: 'driverId', select: 'userId isVerified status' },
          {
            path: 'jeepneyId',
            select: 'capacity status lastKnownLocation plateNumber jeepneyName',
          },
        ],
      });
      if (trip.status !== 'active' || !trip.acceptRequests) {
        throw new ApiError(409, 'Trip not active or not accepting requests');
      }
      if (String(trip.routeId) !== String(route._id)) {
        throw new ApiError(400, 'Route does not match selected trip');
      }
    } else {
      trip = await resolveEligibleTripForRoute({
        routeId: route._id,
        pickupLocation,
      });
    }

    const pendingCount = await PickupRequest.countDocuments({
      tripSessionId: trip._id,
      passengerId: passenger._id,
      status: { $in: ['pending', 'acknowledged'] },
    });
    if (pendingCount >= maxRequestsPerPassengerPerTrip) {
      throw new ApiError(409, 'Too many pending requests for this trip');
    }

    const request = await PickupRequest.create({
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
      stopRef: payload.stopRef,
      pickupLocation,
      destinationStopRef: normalizedDestinationStopRef,
      destinationLocation: {
        type: 'Point',
        coordinates: [Number(lngDestination), Number(latDestination)],
      },
      sourceNote: payload.sourceNote,
      expiresAt: new Date(Date.now() + pickupRequestTtlMinutes * 60 * 1000),
    });

    const tripDriverUser = trip.driverId?.userId
      ? { userId: trip.driverId.userId }
      : await Driver.findById(trip.driverId).select('userId');
    await publishNotification({
      userId: tripDriverUser?.userId,
      type: 'pickup_request_created',
      title: 'New roadside pickup request',
      body:
        `${req.user.fullName || 'Passenger'} requested ` +
        `${payload.stopRef || 'a pickup stop'} to ` +
        `${normalizedDestinationStopRef}`,
      payload: {
        requestId: request._id,
        tripSessionId: trip._id.toString(),
        routeId: route._id.toString(),
        request: serializePickupRequest(request),
      },
      category: 'trip',
    });

    return ok(res, request, 'Pickup request created', 201);
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
    if (request.status === 'completed' || request.status === 'cancelled') {
      throw new ApiError(409, 'Request cannot be acknowledged in current state');
    }
    const trip = await requireTrip(request.tripSessionId);
    if (trip.status !== 'active') {
      throw new ApiError(409, 'Trip is not active for acknowledgment');
    }
    let driver;
    if (req.user.role === DRIVER) {
      driver = await ensureDriverAssignedToTrip(req.user, trip, {
        forbiddenMessage: 'You are not assigned to this request',
      });
      ensureDriverCanHandlePickup({ driver, trip });
    }
    if (!trip.driverId) {
      throw new ApiError(409, 'Trip driver missing');
    }

    const previousStatus = request.status;
    request.status = 'acknowledged';
    request.acknowledgedAt = new Date();
    if (req.user.role === DRIVER) {
      driver ??= await requireCurrentDriver(req.user);
      request.acknowledgedBy = driver?._id || null;
    }
    await request.save();
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
    });
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

    request.status = 'cancelled';
    await request.save();
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
      ensureDriverCanHandlePickup({ driver, trip });
    }
    if (request.status !== 'acknowledged') {
      if (request.status !== 'pending') {
        throw new ApiError(409, 'Only pending/acknowledged requests can be completed');
      }
    }
    const previousStatus = request.status;
    request.status = 'completed';
    request.acknowledgedAt = request.acknowledgedAt || new Date();
    await request.save();
    const existingRideSession = await RideSession.findOne({
      pickupRequestId: request._id,
    });
    const ridePreviousStatus = existingRideSession?.status;
    const rideSession = await RideSession.findOneAndUpdate(
      { pickupRequestId: request._id },
      { status: 'completed', endedAt: new Date() },
      { new: true }
    );
    const passengerUser = await Passenger.findById(request.passengerId).select('userId');
    await publishNotification({
      userId: passengerUser?.userId,
      type: 'pickup_request_completed',
      title: 'Pickup confirmed',
      body: `The driver confirmed your pickup at ${request.stopRef || 'the selected pickup point'}`,
      payload: {
        requestId: request._id,
        tripSessionId: trip._id.toString(),
        previousStatus,
        ridePreviousStatus,
        request: serializePickupRequest(request),
        rideSession: serializeRideSession(rideSession),
      },
      category: 'trip',
    });
    return ok(res, request, 'Pickup request marked completed');
  })
);

module.exports = router;
