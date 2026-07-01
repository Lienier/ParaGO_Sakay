const express = require('express');
const Passenger = require('../models/passenger');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { PASSENGER, ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const RouteModel = require('../models/route');
const { ensureLatLng, ensureObjectId } = require('../utils/validators');
const { hasOwn, isPlainObject } = require('../utils/object');
const { requireCurrentPassenger } = require('../services/routeContext.service');
const {
  processAutomaticBoardingForPassenger,
} = require('../services/automaticBoarding.service');
const {
  processAutomaticOffboardingForPassenger,
} = require('../services/automaticOffboarding.service');
const { serializeRideSession } = require('../utils/realtimePayloads');

const router = express.Router();

router.get(
  '/me',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const profile = await requireCurrentPassenger(req.user);
    return ok(res, profile, 'Passenger profile');
  })
);

router.put(
  '/me',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const payload = req.body || {};
    const updates = {};
    const unset = {};

    if (hasOwn(payload, 'phone')) {
      updates.phone = String(payload.phone || '').trim();
    }
    if (hasOwn(payload, 'photoUrl')) {
      updates.photoUrl = String(payload.photoUrl || '').trim();
    }
    if (hasOwn(payload, 'defaultRouteId')) {
      if (!payload.defaultRouteId) {
        unset.defaultRouteId = '';
      } else {
        ensureObjectId(payload.defaultRouteId, 'defaultRouteId');
        const route = await RouteModel.findById(payload.defaultRouteId).select('_id');
        if (!route) throw new ApiError(404, 'Default route not found');
        updates.defaultRouteId = route._id;
      }
    }
    if (hasOwn(payload, 'emergencyContact')) {
      if (payload.emergencyContact == null || payload.emergencyContact === '') {
        unset.emergencyContact = '';
      } else {
        if (!isPlainObject(payload.emergencyContact)) {
          throw new ApiError(400, 'emergencyContact must be an object');
        }
        updates.emergencyContact = {
          name: String(payload.emergencyContact.name || '').trim(),
          phone: String(payload.emergencyContact.phone || '').trim(),
        };
      }
    }

    const updateAction = {};
    if (Object.keys(updates).length) updateAction.$set = updates;
    if (Object.keys(unset).length) updateAction.$unset = unset;
    if (!Object.keys(updateAction).length) {
      throw new ApiError(400, 'No valid passenger profile fields provided');
    }

    const passenger = await requireCurrentPassenger(req.user, {
      select: '_id',
    });
    const profile = await Passenger.findByIdAndUpdate(
      passenger._id,
      updateAction,
      { new: true, upsert: true, setDefaultsOnInsert: true }
    );
    return ok(res, profile, 'Passenger profile updated');
  })
);

const updatePassengerLocation = async (req, res) => {
  const body = req.body || {};
  ensureLatLng(body.lat, body.lng, 'location');
  const passenger = await requireCurrentPassenger(req.user, {
    select: '_id',
  });
  const now = new Date();
  const profile = await Passenger.findByIdAndUpdate(
    passenger._id,
    {
      $set: {
        lastKnownLocation: {
          type: 'Point',
          coordinates: [Number(body.lng), Number(body.lat)],
        },
        lastSeenAt: now,
      },
    },
    { new: true }
  );
  const boarded = await processAutomaticBoardingForPassenger({
    passengerId: passenger._id,
    now,
  });
  const completed = boarded.length
    ? []
    : await processAutomaticOffboardingForPassenger({
        passengerId: passenger._id,
        now,
      });

  return ok(
    res,
    {
      passenger: profile,
      autoBoardedRideSession: serializeRideSession(boarded[0]),
      autoBoardedCount: boarded.length,
      autoCompletedRideSession: serializeRideSession(completed[0]),
      autoCompletedCount: completed.length,
    },
    'Passenger location updated'
  );
};

for (const method of ['patch', 'post', 'put']) {
  router[method](
    '/me/location',
    authenticate,
    authorize(PASSENGER),
    asyncHandler(updatePassengerLocation)
  );
}

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
