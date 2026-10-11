const express = require('express');
const mongoose = require('mongoose');
const Jeepney = require('../models/jeepney');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { ADMIN, DRIVER, PASSENGER } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');
const {
  buildJeepneyCreatePayload,
  buildJeepneyUpdatePayload,
} = require('../utils/transportPayloads');

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
    const item = await Jeepney.create(buildJeepneyCreatePayload(req.body || {}));
    return ok(res, item, 'Jeepney created', 201);
  })
);

router.put(
  '/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'jeepney id');
    const updates = buildJeepneyUpdatePayload(req.body || {});
    if (!Object.keys(updates).length) {
      throw new ApiError(400, 'No valid jeepney fields provided');
    }
    const session = await mongoose.startSession();
    let item;
    try { await session.withTransaction(async () => {
    if (updates.capacity != null) {
      const Trip = require('../models/tripSession');
      // Boarding and reservations also write these trips, serializing a
      // capacity change with concurrent seat changes.
      await Trip.updateMany({ jeepneyId: req.params.id, status: { $in: ['active', 'scheduled'] } },
        { $inc: { lifecycleRevision: 1 } }, { session });
      const trips = await Trip.find({ jeepneyId: req.params.id, status: { $in: ['active', 'scheduled'] } }).session(session);
      let required = 0;
      for (const trip of trips) {
        const counts = await require('../services/seatAccounting.service').counts(trip, session);
        required += counts.occupied + counts.reserved;
      }
      if (updates.capacity < required) throw new ApiError(409, 'Capacity cannot be lower than the onboard and reserved seats');
    }
    item = await Jeepney.findByIdAndUpdate(
      req.params.id,
      { $set: updates },
      { new: true, runValidators: true, session }
    );
    if (!item) throw new ApiError(404, 'Jeepney not found');
    }); } finally { await session.endSession(); }
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
