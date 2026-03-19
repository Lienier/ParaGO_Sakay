const express = require('express');
const RideSession = require('../models/rideSession');
const Passenger = require('../models/passenger');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER } = require('../constants/roles');
const { validateBoardingAttempt } = require('../services/boarding.service');
const { ensureObjectId, ensureLatLng } = require('../utils/validators');

const router = express.Router();

router.post(
  '/validate',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await Passenger.findOne({ userId: req.user._id });
    if (!passenger) throw new ApiError(404, 'Passenger profile missing');

    const body = req.body || {};
    if (!body.tripSessionId || !body.pickupRequestId) {
      throw new ApiError(400, 'tripSessionId and pickupRequestId are required');
    }
    ensureObjectId(body.tripSessionId, 'tripSessionId');
    ensureObjectId(body.pickupRequestId, 'pickupRequestId');
    ensureLatLng(body.lat, body.lng);
    const result = await validateBoardingAttempt({
      passengerId: passenger._id,
      tripSessionId: body.tripSessionId,
      pickupRequestId: body.pickupRequestId,
      lat: body.lat,
      lng: body.lng,
    });
    return ok(res, result, 'Boarding validated');
  })
);

router.get(
  '/ride-session',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await Passenger.findOne({ userId: req.user._id });
    if (!passenger) throw new ApiError(404, 'Passenger profile missing');
    const sessions = await RideSession.find({ passengerId: passenger._id }).sort({ updatedAt: -1 });
    return ok(res, sessions, 'Passenger ride sessions');
  })
);

module.exports = router;
