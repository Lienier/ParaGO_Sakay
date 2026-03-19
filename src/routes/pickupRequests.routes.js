const express = require('express');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const Route = require('../models/route');
const { publishNotification } = require('../services/notificationPublisher');
const { isRoutePickupNearRoad, pickDefaultRouteCoordinate } = require('../utils/routeGeo');
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
} = require('../config/env');
const { ensureObjectId, ensureLatLng } = require('../utils/validators');

const router = express.Router();

router.post(
  '/',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const payload = req.body || {};
    const passenger = await Passenger.findOne({ userId: req.user._id });
    if (!passenger) throw new ApiError(404, 'Passenger profile not found');

    if (!payload.tripSessionId || !payload.routeId) {
      throw new ApiError(400, 'tripSessionId and routeId required');
    }
    ensureObjectId(payload.tripSessionId, 'tripSessionId');
    ensureObjectId(payload.routeId, 'routeId');
    const route = await Route.findById(payload.routeId);
    if (!route) throw new ApiError(404, 'Route not found');

    const trip = await TripSession.findById(payload.tripSessionId);
    if (!trip || trip.status !== 'active' || !trip.acceptRequests) {
      throw new ApiError(409, 'Trip not active or not accepting requests');
    }
    if (String(trip.routeId) !== String(route._id)) {
      throw new ApiError(400, 'Route does not match selected trip');
    }
    if (trip.driverId) {
      const driver = await Driver.findById(trip.driverId).select('userId isVerified status');
      if (driver && !driver.isVerified) {
        throw new ApiError(409, 'Assigned driver is not verified');
      }
      if (driver && driver.status !== 'active') {
        throw new ApiError(409, 'Assigned driver is not active');
      }
    }

    let pickupLocation = payload.pickupLocation;
    if (!pickupLocation || !Array.isArray(pickupLocation.coordinates) || pickupLocation.coordinates.length < 2) {
      pickupLocation = pickDefaultRouteCoordinate(route);
      if (!pickupLocation) {
        throw new ApiError(400, 'pickupLocation is required for this route');
      }
    }
    const [lngPickup, latPickup] = pickupLocation.coordinates;
    ensureLatLng(latPickup, lngPickup, 'pickupLocation');

    if (!isRoutePickupNearRoad({
      latitude: latPickup,
      longitude: lngPickup,
      route,
      maxDistanceMeters: pickupRoadProximityMeters,
    })) {
      throw new ApiError(400, 'Pickup point must be near the selected route');
    }

    const pendingCount = await PickupRequest.countDocuments({
      tripSessionId: payload.tripSessionId,
      passengerId: passenger._id,
      status: { $in: ['pending', 'acknowledged'] },
    });
    if (pendingCount >= maxRequestsPerPassengerPerTrip) {
      throw new ApiError(409, 'Too many pending requests for this trip');
    }

    const request = await PickupRequest.create({
      passengerId: passenger._id,
      tripSessionId: trip._id,
      routeId: payload.routeId,
      stopRef: payload.stopRef,
      pickupLocation,
      sourceNote: payload.sourceNote,
      expiresAt: new Date(Date.now() + pickupRequestTtlMinutes * 60 * 1000),
    });

    const tripDriverUser = await Driver.findById(trip.driverId).select('userId');
    await publishNotification({
      userId: tripDriverUser?.userId,
      type: 'pickup_request_created',
      title: 'New roadside pickup request',
      body: `${req.user.fullName || 'Passenger'} requested ${payload.stopRef || 'a pickup stop'}`,
      payload: {
        requestId: request._id,
        tripSessionId: trip._id.toString(),
        routeId: route._id.toString(),
      },
      category: 'trip',
    });

    return ok(res, request, 'Pickup request created', 201);
  })
);

router.get(
  '/mine',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await Passenger.findOne({ userId: req.user._id });
    if (!passenger) throw new ApiError(404, 'Passenger profile not found');
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
    const trip = await TripSession.findById(req.params.tripSessionId);
    if (!trip) throw new ApiError(404, 'Trip not found');
    if (req.user.role === DRIVER) {
      const driver = await Driver.findOne({ userId: req.user._id });
      if (!driver || String(driver._id) !== String(trip.driverId)) {
        throw new ApiError(403, 'Driver not assigned to this trip');
      }
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
    const request = await PickupRequest.findById(req.params.id);
    if (!request) throw new ApiError(404, 'Pickup request not found');
    if (request.status === 'completed' || request.status === 'cancelled') {
      throw new ApiError(409, 'Request cannot be acknowledged in current state');
    }
    const trip = await TripSession.findById(request.tripSessionId);
    if (!trip || trip.status !== 'active') {
      throw new ApiError(409, 'Trip is not active for acknowledgment');
    }
    if (req.user.role === DRIVER) {
      const driver = await Driver.findOne({ userId: req.user._id });
      if (!driver || String(driver._id) !== String(trip.driverId)) {
        throw new ApiError(403, 'You are not assigned to this request');
      }
    }
    if (!trip.driverId) {
      throw new ApiError(409, 'Trip driver missing');
    }

    request.status = 'acknowledged';
    request.acknowledgedAt = new Date();
    if (req.user.role === 'DRIVER') {
      const driver = await Driver.findOne({ userId: req.user._id });
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
    const request = await PickupRequest.findById(req.params.id);
    if (!request) throw new ApiError(404, 'Pickup request not found');

    if (req.user.role === PASSENGER) {
      const passenger = await Passenger.findOne({ userId: req.user._id });
      if (!passenger || String(request.passengerId) !== String(passenger._id)) {
        throw new ApiError(403, 'You can only cancel your own request');
      }
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
    const request = await PickupRequest.findById(req.params.id);
    if (!request) throw new ApiError(404, 'Pickup request not found');
    const trip = await TripSession.findById(request.tripSessionId);
    if (!trip) throw new ApiError(404, 'Trip not found for this request');
    if (req.user.role === DRIVER) {
      const driver = await Driver.findOne({ userId: req.user._id });
      if (!driver || String(driver._id) !== String(trip.driverId)) {
        throw new ApiError(403, 'You are not assigned to this request');
      }
    }
    if (request.status !== 'acknowledged') {
      if (request.status !== 'pending') {
        throw new ApiError(409, 'Only pending/acknowledged requests can be completed');
      }
    }
    request.status = 'completed';
    request.acknowledgedAt = request.acknowledgedAt || new Date();
    await request.save();
    await RideSession.findOneAndUpdate(
      { pickupRequestId: request._id },
      { status: 'completed', endedAt: new Date() }
    );
    const passengerUser = await Passenger.findById(request.passengerId).select('userId');
    await publishNotification({
      userId: passengerUser?.userId,
      type: 'pickup_request_completed',
      title: 'Pickup request completed',
      body: `You are now marked as onboard for request ${request.stopRef || 'selected pickup'}`,
      payload: {
        requestId: request._id,
        tripSessionId: trip._id.toString(),
      },
      category: 'trip',
    });
    return ok(res, request, 'Pickup request marked completed');
  })
);

module.exports = router;
