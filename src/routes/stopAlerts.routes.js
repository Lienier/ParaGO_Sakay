const express = require('express');
const StopAlert = require('../models/stopAlert');
const Driver = require('../models/driver');
const TripSession = require('../models/tripSession');
const Passenger = require('../models/passenger');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { DRIVER_ERROR_CODES, driverError } = require('../utils/driverError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const { createStopAlert } = require('../services/stopAlert.service');
const { publishNotification } = require('../services/notificationPublisher');
const { ensureObjectId, ensureLatLng } = require('../utils/validators');
const { serializeStopAlert } = require('../utils/realtimePayloads');
const {
  requireCurrentPassenger,
  requireTrip,
  ensureDriverAssignedToTrip,
} = require('../services/routeContext.service');

const router = express.Router();

router.post(
  '/',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await requireCurrentPassenger(req.user);
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

    try { await publishNotification({
      userId: driver?.userId,
      type: 'stop_alert_created',
      title: 'New passenger stop alert',
      body: `${req.user.fullName || 'Passenger'} requested to unload near ${body.stopRef || 'the selected stop'}.`,
      payload: {
        stopAlertId: alert._id.toString(),
        tripSessionId: alert.tripSessionId.toString(),
        routeId: alert.routeId.toString(),
        stopAlert: serializeStopAlert(alert),
      },
      category: 'ride',
    }); } catch (_) { console.error('[Stop alert] Notification delivery failed after the alert was saved'); }

    return ok(res, alert, 'Stop alert sent', 201);
  })
);

router.get(
  '/trip/:tripSessionId',
  authenticate,
  authorize(DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.tripSessionId, 'tripSessionId');
    const trip = await requireTrip(req.params.tripSessionId);
    if (req.user.role === DRIVER) {
      await ensureDriverAssignedToTrip(req.user, trip, {
        forbiddenMessage: 'Not authorized for this trip',
      });
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
    if (!alert) throw driverError(404, DRIVER_ERROR_CODES.STOP_ALERT_NOT_FOUND,
      'This stop alert is no longer available.', 'Refresh the alert list.');
    const trip = await requireTrip(alert.tripSessionId, {
      notFoundMessage: 'Trip not found for this stop alert',
    });
    const driver = req.user.role === DRIVER
      ? await ensureDriverAssignedToTrip(req.user, trip)
      : null;
    if (alert.status === 'acknowledged') {
      return ok(res, alert, 'Stop alert already acknowledged');
    }
    if (alert.status === 'dismissed') {
      throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'This stop alert was already dismissed.', 'Refresh the alert list before trying again.');
    }

    const previousStatus = alert.status;
    const acknowledgedAt = new Date();
    let acknowledgedAlert = await StopAlert.findOneAndUpdate(
      {
        _id: alert._id,
        status: { $in: ['sent', 'seen'] },
      },
      {
        $set: {
          status: 'acknowledged',
          acknowledgedAt,
          acknowledgedBy: driver?._id,
        },
      },
      {
        new: true,
      }
    );
    if (!acknowledgedAlert) {
      const latestAlert = await StopAlert.findById(req.params.id);
      if (!latestAlert) {
        throw driverError(404, DRIVER_ERROR_CODES.STOP_ALERT_NOT_FOUND,
          'This stop alert is no longer available.', 'Refresh the alert list.');
      }
      if (latestAlert.status === 'acknowledged') {
        return ok(res, latestAlert, 'Stop alert already acknowledged');
      }
      if (latestAlert.status === 'dismissed') {
        throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
          'This stop alert was already dismissed.', 'Refresh the alert list before trying again.');
      }
      throw driverError(409, DRIVER_ERROR_CODES.DUPLICATE_OPERATION,
        'This stop alert is already being acknowledged.', 'Refresh the alert list before trying again.');
    }

    const passenger = await Passenger.findById(alert.passengerId).select('userId');
    await publishNotification({
      userId: passenger?.userId,
      type: 'stop_alert_acknowledged',
      title: 'Stop alert acknowledged',
      body: `${req.user.fullName || 'Driver'} is preparing to help stopping soon.`,
      payload: {
        stopAlertId: acknowledgedAlert._id.toString(),
        tripSessionId: acknowledgedAlert.tripSessionId.toString(),
        previousStatus,
        stopAlert: serializeStopAlert(acknowledgedAlert),
      },
      category: 'ride',
    });

    return ok(res, acknowledgedAlert, 'Stop alert acknowledged');
  })
);

module.exports = router;
