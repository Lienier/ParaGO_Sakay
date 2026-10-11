const express = require('express');
const RouteModel = require('../models/route');
const TripSession = require('../models/tripSession');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');
const {
  buildRouteCreatePayload,
  buildRouteUpdatePayload,
} = require('../utils/transportPayloads');
const { redisKey } = require('../services/redis.service');
const {
  getOrLoadCachedRead,
  invalidateCachedRead,
} = require('../services/readCache.service');

const router = express.Router();
const routeListCacheKey = redisKey('read', 'routes', 'all');

const buildRoutePathSnapshot = (route) => {
  const coordinates = Array.isArray(route?.path?.coordinates)
    ? route.path.coordinates
    : [];

  if (coordinates.length < 2) {
    return undefined;
  }

  return {
    type: 'LineString',
    coordinates: coordinates.map((entry) => [Number(entry[0]), Number(entry[1])]),
  };
};

router.get(
  '/',
  authenticate,
  asyncHandler(async (_req, res) => {
    const routes = await getOrLoadCachedRead({
      key: routeListCacheKey,
      ttlSeconds: 30,
      loader: () => RouteModel.find().sort({ name: 1 }).lean(),
    });
    return ok(res, routes.value, 'Route list');
  })
);

router.post(
  '/',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const route = await RouteModel.create(buildRouteCreatePayload(req.body || {}));
    await invalidateCachedRead(routeListCacheKey);
    return ok(res, route, 'Route created', 201);
  })
);

router.put(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'route id');
    const updates = buildRouteUpdatePayload(req.body || {});
    if (!Object.keys(updates).length) {
      throw new ApiError(400, 'No valid route fields provided');
    }
    if (updates.path && await TripSession.exists({ routeId: req.params.id, status: { $in: ['active', 'scheduled'] } })) {
      throw new ApiError(409, 'End the active trips before changing the route path. Current pickup and drop-off locations must stay valid.');
    }
    const updated = await RouteModel.findByIdAndUpdate(
      req.params.id,
      { $set: updates },
      { new: true, runValidators: true }
    );
    if (!updated) throw new ApiError(404, 'Route not found');
    await TripSession.updateMany(
      {
        routeId: updated._id,
        status: { $in: ['scheduled', 'active'] },
      },
      {
        $set: {
          routePathSnapshot: buildRoutePathSnapshot(updated),
        },
      }
    );
    await invalidateCachedRead(routeListCacheKey);
    return ok(res, updated, 'Route updated');
  })
);

router.delete(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'route id');
    const updated = await RouteModel.findByIdAndUpdate(
      req.params.id,
      { status: 'inactive' },
      { new: true }
    );
    if (!updated) throw new ApiError(404, 'Route not found');
    await invalidateCachedRead(routeListCacheKey);
    return ok(res, updated, 'Route deactivated');
  })
);

module.exports = router;
