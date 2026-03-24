const express = require('express');
const StopAlert = require('../models/stopAlert');
const Driver = require('../models/driver');
const TripSession = require('../models/tripSession');
const Passenger = require('../models/passenger');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const { createStopAlert } = require('../services/stopAlert.service');
const { publishNotification } = require('../services/notificationPublisher');
const { ensureObjectId, ensureLatLng } = require('../utils/validators');

const router = express.Router();

router.post(
  '/',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await Passenger.findOne({ userId: req.user._id });
    if (!passenger) throw new ApiError(404, 'Passenger profile missing');
    const body = req.body || {};
    if (!body.tripSessionId || !body.stopRef) {
      throw new ApiError(400, 'tripSessionId and stopRef are required');
    }
    ensureObjectId(body.tripSessionId, 'tripSessionId');
    if (body.location?.coordinates?.length === 2) {
      const [lng, lat] = body.location.coordinates;
      ensureLatLng(lat, lng, 'location');
    }
    const alert = await createStopAlert({
      passengerId: passenger._id,
      tripSessionId: body.tripSessionId,
      stopRef: body.stopRef,
      note: body.note,
      location: body.location,
    });

    const trip = await TripSession.findById(body.tripSessionId).select('driverId');
    const driver = trip?.driverId
      ? await Driver.findById(trip.driverId).select('userId')
      : null;

    await publishNotification({
      userId: driver?.userId,
      type: 'stop_alert_created',
      title: 'New passenger stop alert',
      body: `${req.user.fullName || 'Passenger'} requested to unload near ${body.stopRef || 'the selected stop'}.`,
      payload: {
        stopAlertId: alert._id.toString(),
        tripSessionId: alert.tripSessionId.toString(),
        routeId: alert.routeId.toString(),
      },
      category: 'ride',
    });

    return ok(res, alert, 'Stop alert sent', 201);
  })
);

router.get(
  '/trip/:tripSessionId',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.tripSessionId, 'tripSessionId');
    const trip = await TripSession.findById(req.params.tripSessionId);
    if (!trip) throw new ApiError(404, 'Trip not found');
    if (req.user.role === DRIVER) {
      const driver = await Driver.findOne({ userId: req.user._id });
      if (!driver || String(driver._id) !== String(trip.driverId)) {
        throw new ApiError(403, 'Not authorized for this trip');
      }
    }
    const alerts = await StopAlert.find({
      tripSessionId: req.params.tripSessionId,
    }).sort({ createdAt: -1 });
    return ok(res, alerts, 'Trip stop alerts');
  })
);

router.patch(
  '/:id/acknowledge',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'stop alert id');
    const alert = await StopAlert.findById(req.params.id);
    if (!alert) throw new ApiError(404, 'Stop alert not found');
    const trip = await TripSession.findById(alert.tripSessionId);
    if (!trip) throw new ApiError(404, 'Trip not found for this stop alert');
    if (req.user.role === DRIVER) {
      const driver = await Driver.findOne({ userId: req.user._id });
      if (!driver || String(driver._id) !== String(trip.driverId)) {
        throw new ApiError(403, 'You are not assigned to this trip');
      }
    }

    alert.status = 'acknowledged';
    alert.acknowledgedAt = new Date();
    await alert.save();

    const passenger = await Passenger.findById(alert.passengerId).select('userId');
    await publishNotification({
      userId: passenger?.userId,
      type: 'stop_alert_acknowledged',
      title: 'Stop alert acknowledged',
      body: `${req.user.fullName || 'Driver'} is preparing to help stopping soon.`,
      payload: {
        stopAlertId: alert._id.toString(),
        tripSessionId: alert.tripSessionId.toString(),
      },
      category: 'ride',
    });

    return ok(res, alert, 'Stop alert acknowledged');
  })
);

module.exports = router;
