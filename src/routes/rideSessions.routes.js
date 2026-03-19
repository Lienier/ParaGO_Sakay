const express = require('express');
const RideSession = require('../models/rideSession');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const TripSession = require('../models/tripSession');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const { ensureObjectId } = require('../utils/validators');
const { publishNotification } = require('../services/notificationPublisher');

const router = express.Router();

router.get(
  '/mine',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await Passenger.findOne({ userId: req.user._id });
    if (!passenger) throw new ApiError(404, 'Passenger profile missing');
    const sessions = await RideSession.find({ passengerId: passenger._id }).sort({ createdAt: -1 });
    return ok(res, sessions, 'My ride sessions');
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
        throw new ApiError(403, 'Not authorized for this trip');
      }
    }
    const sessions = await RideSession.find({ tripSessionId: req.params.tripSessionId }).sort({
      status: 1,
      createdAt: -1,
    });
    return ok(res, sessions, 'Trip ride sessions');
  })
);

router.patch(
  '/:id/complete',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'ride session id');
    const session = await RideSession.findById(req.params.id);
    if (!session) throw new ApiError(404, 'Ride session not found');
    const trip = await TripSession.findById(session.tripSessionId);
    if (!trip) throw new ApiError(404, 'Trip not found');
    if (req.user.role === DRIVER) {
      const driver = await Driver.findOne({ userId: req.user._id });
      if (!driver || String(driver._id) !== String(trip.driverId)) {
        throw new ApiError(403, 'You are not assigned to this trip');
      }
    }
    if (session.status === 'completed') {
      throw new ApiError(409, 'Ride session already completed');
    }
    session.status = 'completed';
    session.endedAt = new Date();
    session.canSendStopAlert = false;
    await session.save();
    const passenger = await Passenger.findById(session.passengerId).select('userId');
    await publishNotification({
      userId: passenger?.userId,
      type: 'ride_completed',
      title: 'Ride completed',
      body: 'Your onboard ride session has been completed.',
      payload: {
        rideSessionId: session._id.toString(),
        tripSessionId: session.tripSessionId.toString(),
      },
      category: 'ride',
    });
    return ok(res, session, 'Ride session completed');
  })
);

module.exports = router;
