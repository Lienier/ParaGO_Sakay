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

const startOfUtcDay = (value) =>
  new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()));

const formatUtcDayKey = (value) => startOfUtcDay(value).toISOString().slice(0, 10);

const formatUtcDayLabel = (value) =>
  value.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });

const buildDailyTimeline = ({ from, to, boardedRows, unloadedRows }) => {
  const boardedMap = new Map(
    boardedRows.map((entry) => [entry._id, Number(entry.count || 0)])
  );
  const unloadedMap = new Map(
    unloadedRows.map((entry) => [entry._id, Number(entry.count || 0)])
  );
  const timeline = [];
  const endDay = startOfUtcDay(to);

  for (
    let cursor = startOfUtcDay(from);
    cursor.getTime() <= endDay.getTime();
    cursor = new Date(cursor.getTime() + 24 * 60 * 60 * 1000)
  ) {
    const dayKey = formatUtcDayKey(cursor);
    timeline.push({
      day: dayKey,
      label: formatUtcDayLabel(cursor),
      boarded: boardedMap.get(dayKey) || 0,
      unloaded: unloadedMap.get(dayKey) || 0,
    });
  }

  return timeline;
};

const normalizeTopStopRows = (rows = []) =>
  rows.map((entry) => ({
    label: entry._id?.toString() || 'Unknown stop',
    count: Number(entry.count || 0),
  }));

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

const resolveTripIdsForRoute = async (routeId) => {
  if (!routeId) {
    return null;
  }
  return TripSession.find({ routeId }).distinct('_id');
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

router.get(
  '/passenger-flow',
  asyncHandler(async (req, res) => {
    const { from, to, routeId } = parseDates(req);
    const tripIds = await resolveTripIdsForRoute(routeId);

    const boardedMatch = {
      boardedAt: { $gte: from, $lte: to },
    };
    const unloadedMatch = {
      endedAt: { $gte: from, $lte: to },
    };

    if (tripIds) {
      boardedMatch.tripSessionId = { $in: tripIds };
      unloadedMatch.tripSessionId = { $in: tripIds };
    }

    const [
      totalBoarded,
      totalUnloaded,
      boardedByDay,
      unloadedByDay,
      topBoardingStops,
      topUnloadStops,
    ] = await Promise.all([
      RideSession.countDocuments(boardedMatch),
      RideSession.countDocuments(unloadedMatch),
      RideSession.aggregate([
        { $match: boardedMatch },
        {
          $group: {
            _id: {
              $dateToString: {
                format: '%Y-%m-%d',
                date: '$boardedAt',
                timezone: 'UTC',
              },
            },
            count: { $sum: 1 },
          },
        },
        { $sort: { _id: 1 } },
      ]),
      RideSession.aggregate([
        { $match: unloadedMatch },
        {
          $group: {
            _id: {
              $dateToString: {
                format: '%Y-%m-%d',
                date: '$endedAt',
                timezone: 'UTC',
              },
            },
            count: { $sum: 1 },
          },
        },
        { $sort: { _id: 1 } },
      ]),
      RideSession.aggregate([
        { $match: boardedMatch },
        {
          $project: {
            stopRef: '$fareSnapshot.boardingStopRef',
          },
        },
        { $match: { stopRef: { $nin: [null, ''] } } },
        { $group: { _id: '$stopRef', count: { $sum: 1 } } },
        { $sort: { count: -1, _id: 1 } },
        { $limit: 5 },
      ]),
      RideSession.aggregate([
        { $match: unloadedMatch },
        {
          $project: {
            stopRef: {
              $ifNull: ['$fareSnapshot.destinationStopRef', '$destinationStopRef'],
            },
          },
        },
        { $match: { stopRef: { $nin: [null, ''] } } },
        { $group: { _id: '$stopRef', count: { $sum: 1 } } },
        { $sort: { count: -1, _id: 1 } },
        { $limit: 5 },
      ]),
    ]);

    const normalizedBoardingStops = normalizeTopStopRows(topBoardingStops);
    const normalizedUnloadStops = normalizeTopStopRows(topUnloadStops);

    return ok(
      res,
      {
        from,
        to,
        summary: {
          totalBoarded,
          totalUnloaded,
          topBoardingStop: normalizedBoardingStops[0] || null,
          topUnloadStop: normalizedUnloadStops[0] || null,
        },
        daily: buildDailyTimeline({
          from,
          to,
          boardedRows: boardedByDay,
          unloadedRows: unloadedByDay,
        }),
        topBoardingStops: normalizedBoardingStops,
        topUnloadStops: normalizedUnloadStops,
      },
      'Passenger flow report'
    );
  })
);

module.exports = router;
