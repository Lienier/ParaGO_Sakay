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

const router = express.Router();

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
  asyncHandler(async (req, res) => {
    const routes = await RouteModel.find().sort({ name: 1 });
    return ok(res, routes, 'Route list');
  })
);

router.post(
  '/',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const route = await RouteModel.create(buildRouteCreatePayload(req.body || {}));
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
    return ok(res, updated, 'Route deactivated');
  })
);

module.exports = router;
