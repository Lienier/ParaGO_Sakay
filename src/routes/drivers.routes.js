const express = require('express');
const Driver = require('../models/driver');
const TripSession = require('../models/tripSession');
const Jeepney = require('../models/jeepney');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { DRIVER, ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { ensureLatLng } = require('../utils/validators');
const { hasOwn } = require('../utils/object');
const validateObjectId = require('../middlewares/validateObjectId');
const { requireCurrentDriver } = require('../services/routeContext.service');

const router = express.Router();

router.get(
  '/me',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const profile = await requireCurrentDriver(req.user);
    return ok(res, profile, 'Driver profile');
  })
);

const updateDriverStatus = async (req, res) => {
  const status = String(req.body?.status || '').toLowerCase();
  if (!['active', 'inactive'].includes(status)) {
    throw new ApiError(400, 'status must be one of: active, inactive');
  }
  let profile = await Driver.findOneAndUpdate(
    { userId: req.user._id },
    { $set: { status } },
    { new: true }
  );
  if (!profile) {
    profile = await Driver.create({
      userId: req.user._id,
      status,
    });
  }
  return ok(res, { status: profile.status }, 'Driver status updated');
};

for (const method of ['patch', 'post', 'put']) {
  router[method](
    '/me/status',
    authenticate,
    authorize(DRIVER),
    asyncHandler(updateDriverStatus)
  );
}

router.get(
  '/me/active-trips',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const driver = await requireCurrentDriver(req.user, {
      notFoundMessage: 'Driver record missing',
    });
    const trips = await TripSession.find({
      driverId: driver._id,
      status: { $in: ['active', 'scheduled'] },
    });
    return ok(res, trips, 'Driver active/scheduled trips');
  })
);

router.put(
  '/me',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const updates = {};
    if (hasOwn(req.body, 'licenseNumber')) {
      updates.licenseNumber = String(req.body.licenseNumber || '').trim();
    }
    if (hasOwn(req.body, 'employeeNumber')) {
      updates.employeeNumber = String(req.body.employeeNumber || '').trim();
    }
    if (hasOwn(req.body, 'phone')) {
      updates.phone = String(req.body.phone || '').trim();
    }
    if (!Object.keys(updates).length) {
      throw new ApiError(400, 'No valid driver profile fields provided');
    }

    const profile = await Driver.findOneAndUpdate(
      { userId: req.user._id },
      { $set: updates },
      { new: true, upsert: true, setDefaultsOnInsert: true }
    );
    return ok(res, profile, 'Driver profile updated');
  })
);

const updateDriverJeepneyLocation = async (req, res) => {
  const body = req.body || {};
  ensureLatLng(body.lat, body.lng, 'location');

  const driver = await requireCurrentDriver(req.user);

  let jeepneyId = driver.assignedJeepneyId;
  if (!jeepneyId) {
    const linkedJeepney = await Jeepney.findOne({ currentDriverId: driver._id })
      .select('_id')
      .sort({ updatedAt: -1, createdAt: -1 });
    if (linkedJeepney) {
      jeepneyId = linkedJeepney._id;
    }
  }
  if (!jeepneyId) {
    const activeTrip = await TripSession.findOne({
      driverId: driver._id,
      status: { $in: ['active', 'scheduled'] },
    })
      .select('jeepneyId')
      .sort({ createdAt: -1 });
    if (!activeTrip || !activeTrip.jeepneyId) {
      throw new ApiError(
        404,
        'No jeepney found for this driver. Set a jeepney assignment first.'
      );
    }
    jeepneyId = activeTrip.jeepneyId;
  }

  const jeepney = await Jeepney.findByIdAndUpdate(
    jeepneyId,
    {
      lastKnownLocation: {
        type: 'Point',
        coordinates: [Number(body.lng), Number(body.lat)],
      },
      lastSeenAt: new Date(),
    },
    { new: true }
  );
  if (!jeepney) {
    throw new ApiError(404, 'Jeepney location target not found');
  }

  return ok(res, jeepney, 'Location updated');
};

const locationMethods = ['patch', 'post', 'put'];
for (const method of locationMethods) {
  router[method](
    '/me/location',
    authenticate,
    authorize(DRIVER),
    asyncHandler(updateDriverJeepneyLocation)
  );
  router[method](
    '/location',
    authenticate,
    authorize(DRIVER),
    asyncHandler(updateDriverJeepneyLocation)
  );
}

router.patch(
  '/:id/verify',
  authenticate,
  authorize(ADMIN),
  validateObjectId(),
  asyncHandler(async (req, res) => {
    const profile = await Driver.findById(req.params.id);
    if (!profile) throw new ApiError(404, 'Driver profile not found');
    profile.isVerified = req.body.isVerified ?? true;
    await profile.save();
    return ok(res, profile, 'Driver verification updated');
  })
);

module.exports = router;
