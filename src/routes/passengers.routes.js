const express = require('express');
const Passenger = require('../models/passenger');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { PASSENGER, ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');

const router = express.Router();

router.get(
  '/me',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const profile = await Passenger.findOne({ userId: req.user._id });
    return ok(res, profile, 'Passenger profile');
  })
);

router.put(
  '/me',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const payload = req.body || {};
    const profile = await Passenger.findOneAndUpdate(
      { userId: req.user._id },
      { $set: payload },
      { new: true }
    );
    return ok(res, profile, 'Passenger profile updated');
  })
);

router.get(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const profile = await Passenger.findById(req.params.id);
    if (!profile) throw new ApiError(404, 'Passenger profile not found');
    return ok(res, profile, 'Passenger profile');
  })
);

module.exports = router;
