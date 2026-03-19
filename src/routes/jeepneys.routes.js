const express = require('express');
const Jeepney = require('../models/jeepney');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ADMIN, DRIVER, PASSENGER } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');

const router = express.Router();

router.get(
  '/',
  authenticate,
  asyncHandler(async (req, res) => {
    const jeepneys = await Jeepney.find().sort({ createdAt: -1 });
    return ok(res, jeepneys, 'Jeepney list');
  })
);

router.post(
  '/',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const item = await Jeepney.create(req.body || {});
    return ok(res, item, 'Jeepney created', 201);
  })
);

router.put(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'jeepney id');
    const item = await Jeepney.findByIdAndUpdate(req.params.id, req.body || {}, { new: true });
    if (!item) throw new ApiError(404, 'Jeepney not found');
    return ok(res, item, 'Jeepney updated');
  })
);

router.delete(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'jeepney id');
    const item = await Jeepney.findByIdAndUpdate(
      req.params.id,
      { status: 'inactive' },
      { new: true }
    );
    if (!item) throw new ApiError(404, 'Jeepney not found');
    return ok(res, item, 'Jeepney deactivated');
  })
);

router.get(
  '/active/for-passenger',
  authenticate,
  authorize(PASSENGER, DRIVER),
  asyncHandler(async (_req, res) => {
    const jeepneys = await Jeepney.find({ status: 'active' });
    return ok(res, jeepneys, 'Active jeepneys');
  })
);

module.exports = router;
