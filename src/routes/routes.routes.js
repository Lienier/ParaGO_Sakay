const express = require('express');
const RouteModel = require('../models/route');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');

const router = express.Router();

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
    const route = await RouteModel.create(req.body || {});
    return ok(res, route, 'Route created', 201);
  })
);

router.put(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'route id');
    const updated = await RouteModel.findByIdAndUpdate(req.params.id, req.body || {}, { new: true });
    if (!updated) throw new ApiError(404, 'Route not found');
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
