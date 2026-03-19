const express = require('express');
const mongoose = require('mongoose');
const { ADMIN } = require('../constants/roles');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const StopAlert = require('../models/stopAlert');
const TripSession = require('../models/tripSession');

const router = express.Router();

router.use(authenticate, authorize(ADMIN));

const parseDates = (req) => {
  const from = req.query.from ? new Date(req.query.from) : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const to = req.query.to ? new Date(req.query.to) : new Date();
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
    throw new ApiError(400, 'Invalid date range');
  }
  const routeId = req.query.routeId ? String(req.query.routeId) : null;
  if (routeId && !mongoose.Types.ObjectId.isValid(routeId)) {
    throw new ApiError(400, 'Invalid routeId');
  }
  return { from, to, routeId };
};

router.get(
  '/requests',
  asyncHandler(async (req, res) => {
    const { from, to, routeId } = parseDates(req);
    const match = { createdAt: { $gte: from, $lte: to } };
    if (routeId) match.routeId = routeId;

    const [rows, total] = await Promise.all([
      PickupRequest.aggregate([{ $match: match }, { $group: { _id: '$status', count: { $sum: 1 } } }]),
      PickupRequest.countDocuments(match),
    ]);
    return ok(res, { total, byStatus: rows }, 'Pickup request report');
  })
);

router.get(
  '/boarding',
  asyncHandler(async (req, res) => {
    const { from, to, routeId } = parseDates(req);
    const match = { createdAt: { $gte: from, $lte: to } };
    if (routeId) {
      const tripIds = await TripSession.find({ routeId }).distinct('_id');
      match.tripSessionId = { $in: tripIds };
    }
    const [rows, total] = await Promise.all([
      RideSession.aggregate([{ $match: match }, { $group: { _id: '$status', count: { $sum: 1 } } }]),
      RideSession.countDocuments(match),
    ]);
    return ok(res, { total, byStatus: rows }, 'Boarding/ride session report');
  })
);

router.get(
  '/alerts',
  asyncHandler(async (req, res) => {
    const { from, to, routeId } = parseDates(req);
    const match = { createdAt: { $gte: from, $lte: to } };
    if (routeId) match.routeId = routeId;
    const [rows, total] = await Promise.all([
      StopAlert.aggregate([{ $match: match }, { $group: { _id: '$status', count: { $sum: 1 } } }]),
      StopAlert.countDocuments(match),
    ]);
    return ok(res, { total, byStatus: rows }, 'Stop alert report');
  })
);

router.get(
  '/trip-activity',
  asyncHandler(async (req, res) => {
    const { from, to, routeId } = parseDates(req);
    const match = { createdAt: { $gte: from, $lte: to } };
    if (routeId) match.routeId = routeId;
    const [rows, total] = await Promise.all([
      TripSession.aggregate([{ $match: match }, { $group: { _id: '$status', count: { $sum: 1 } } }]),
      TripSession.countDocuments(match),
    ]);
    return ok(res, { total, byStatus: rows }, 'Trip activity report');
  })
);

router.get(
  '/route-demand',
  asyncHandler(async (req, res) => {
    const { from, to } = parseDates(req);
    const rows = await PickupRequest.aggregate([
      { $match: { createdAt: { $gte: from, $lte: to } } },
      { $group: { _id: '$routeId', totalRequests: { $sum: 1 } } },
      { $sort: { totalRequests: -1 } },
      { $limit: 100 },
    ]);
    return ok(
      res,
      {
        from,
        to,
        routes: rows,
      },
      'Route demand report'
    );
  })
);

module.exports = router;
