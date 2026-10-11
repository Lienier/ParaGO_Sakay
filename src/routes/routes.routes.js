const express = require('express');
const RouteModel = require('../models/route');
const TripSession = require('../models/tripSession');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const terminalQueue = require('../services/terminalQueue.service');
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
    // Use the same route lock as trip creation: a trip cannot appear between
    // the geometry check and the route write. Trip snapshots stay immutable.
    const updated = await terminalQueue.transaction(req.params.id, async session => {
      const current = await RouteModel.findById(req.params.id).session(session);
      if (!current) throw new ApiError(404, 'Route not found');
      const pathChanged = updates.path && (
        updates.path.type !== current.path?.type ||
        JSON.stringify(updates.path.coordinates) !== JSON.stringify(current.path?.coordinates)
      );
      if (pathChanged && await TripSession.exists({
        routeId: req.params.id, status: { $in: ['active', 'scheduled'] },
      }).session(session)) {
        throw new ApiError(409, 'End the active trips before changing the route path. Current pickup and drop-off locations must stay valid.');
      }
      return RouteModel.findByIdAndUpdate(req.params.id, { $set: updates }, {
        new: true, runValidators: true, session,
      });
    }, { publishChanges: false });
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
