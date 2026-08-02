const express = require('express');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const User = require('../models/user');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const { ensureObjectId } = require('../utils/validators');
const {
  invalidateAuthenticatedUser,
} = require('../services/authUserCache.service');

const router = express.Router();
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

router.get(
  '/passengers',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (_req, res) => {
    const users = await User.find({ role: PASSENGER }).select('-passwordHash');
    return ok(res, users, 'Passengers list');
  })
);

router.get(
  '/drivers',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (_req, res) => {
    const users = await User.find({ role: DRIVER }).select('-passwordHash');
    return ok(res, users, 'Drivers list');
  })
);

router.get(
  '/admins',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (_req, res) => {
    const users = await User.find({ role: ADMIN }).select('-passwordHash');
    return ok(res, users, 'Admins list');
  })
);

router.get(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'user id');
    const user = await User.findById(req.params.id).select('-passwordHash');
    if (!user) throw new ApiError(404, 'User not found');
    return ok(res, user, 'User profile');
  })
);

router.patch(
  '/:id/status',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const { status } = req.body || {};
    if (!['active', 'suspended', 'deactivated'].includes(String(status || ''))) {
      throw new ApiError(400, 'status must be one of: active, suspended, deactivated');
    }
    ensureObjectId(req.params.id, 'user id');
    const user = await User.findById(req.params.id);
    if (!user) throw new ApiError(404, 'User not found');
    user.status = status;
    await user.save();
    await invalidateAuthenticatedUser(user._id);
    return ok(res, user, 'User status updated');
  })
);

router.put(
  '/me',
  authenticate,
  asyncHandler(async (req, res) => {
    const user = await User.findById(req.user._id);
    if (!user) throw new ApiError(404, 'User not found');

    if (req.body.fullName !== undefined) {
      const fullName = String(req.body.fullName || '').trim();
      if (!fullName) {
        throw new ApiError(400, 'fullName cannot be empty');
      }
      user.fullName = fullName;
    }
    if (req.body.email !== undefined) {
      const email = String(req.body.email || '').trim().toLowerCase();
      if (!emailPattern.test(email)) {
        throw new ApiError(400, 'Invalid email format');
      }
      const existingUser = await User.findOne({
        email,
        _id: { $ne: user._id },
      }).select('_id');
      if (existingUser) {
        throw new ApiError(409, 'Email already registered');
      }
      user.email = email;
    }

    await user.save();
    await invalidateAuthenticatedUser(user._id);
    return ok(res, { fullName: user.fullName, email: user.email }, 'Profile updated');
  })
);

router.delete(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'user id');
    const user = await User.findById(req.params.id);
    if (!user) throw new ApiError(404, 'User not found');
    user.status = 'deactivated';
    await user.save();
    await invalidateAuthenticatedUser(user._id);
    return ok(res, null, 'User deactivated');
  })
);

module.exports = router;
