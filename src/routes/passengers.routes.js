const express = require('express');
const Passenger = require('../models/passenger');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { apiRateLimiters } = require('../middlewares/rateLimits');
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
const savedPlaces = require('../services/savedPlaces.service');
router.get('/me/saved-places', authenticate, authorize(PASSENGER), asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return ok(res, await savedPlaces.list(req.user._id), 'Saved places');
}));
router.post('/me/saved-places', authenticate, authorize(PASSENGER), asyncHandler(async (req, res) =>
  ok(res, await savedPlaces.add(req.user._id, req.body), 'Place saved')));
router.delete('/me/saved-places/:placeId', authenticate, authorize(PASSENGER), asyncHandler(async (req, res) =>
  ok(res, await savedPlaces.remove(req.user._id, req.params.placeId), 'Place removed')));

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
  const capturedAt = body.capturedAt == null ? now : new Date(body.capturedAt);
  const age = now - capturedAt;
  if (!Number.isFinite(age) || age < 0 || age > 15000) {
    throw new ApiError(409, 'Fresh passenger GPS is required. Refresh location and try again');
  }
  const profile = await Passenger.findOneAndUpdate(
    { _id: passenger._id, $or: [{lastSeenAt: {$lt: capturedAt}}, {lastSeenAt: {$exists: false}}, {lastSeenAt: null}] },
    {
      $set: {
        lastKnownLocation: {
          type: 'Point',
          coordinates: [Number(body.lng), Number(body.lat)],
        },
        lastSeenAt: capturedAt,
      },
    },
    { new: true }
  );
  if (!profile) {
    return ok(res, { accepted: false, autoBoardedCount: 0, autoCompletedCount: 0 }, 'Older or duplicate GPS sample ignored');
  }
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
    apiRateLimiters.passengerLocation,
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
