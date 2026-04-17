const express = require('express');
const RideSession = require('../models/rideSession');
const Passenger = require('../models/passenger');
const StopAlert = require('../models/stopAlert');
const TripSession = require('../models/tripSession');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const { ensureObjectId } = require('../utils/validators');
const { publishNotification } = require('../services/notificationPublisher');
const { serializeRideSession } = require('../utils/realtimePayloads');
const {
  requireCurrentPassenger,
  requireTrip,
  requireRideSession,
  ensureDriverAssignedToTrip,
  ensurePassengerOwnsRideSession,
} = require('../services/routeContext.service');

const router = express.Router();

const hasValidGeoPoint = (value) => {
  const coordinates = Array.isArray(value?.coordinates) ? value.coordinates : [];
  if (coordinates.length !== 2) {
    return false;
  }

  const [lng, lat] = coordinates.map((entry) => Number(entry));
  return (
    Number.isFinite(lat) &&
    lat >= -90 &&
    lat <= 90 &&
    Number.isFinite(lng) &&
    lng >= -180 &&
    lng <= 180
  );
};

router.get(
  '/mine',
  authenticate,
  authorize(PASSENGER),
  asyncHandler(async (req, res) => {
    const passenger = await requireCurrentPassenger(req.user);
    const sessions = await RideSession.find({ passengerId: passenger._id }).sort({ createdAt: -1 });
    return ok(res, sessions, 'My ride sessions');
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
    const sessions = await RideSession.find({ tripSessionId: req.params.tripSessionId }).sort({
      status: 1,
      createdAt: -1,
    });
    return ok(res, sessions, 'Trip ride sessions');
  })
);

router.patch(
  '/:id/complete',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'ride session id');
    const session = await requireRideSession(req.params.id);
    const trip = await requireTrip(session.tripSessionId);
    if (req.user.role === DRIVER) {
      await ensureDriverAssignedToTrip(req.user, trip);
    } else if (req.user.role === PASSENGER) {
      await ensurePassengerOwnsRideSession(req.user, session, {
        forbiddenMessage: 'You can only complete your own ride session',
      });
    }
    if (session.status === 'completed') {
      throw new ApiError(409, 'Ride session already completed');
    }
    if (session.status !== 'onboard') {
      throw new ApiError(409, 'Only onboard ride sessions can be completed');
    }
    const previousStatus = session.status;
    const endedAt = new Date();
    const update = {
      $set: {
        status: 'completed',
        endedAt,
        canSendStopAlert: false,
      },
    };
    if (!hasValidGeoPoint(session.destinationLocation)) {
      update.$unset = { destinationLocation: 1 };
    }

    const completedSession = await RideSession.findByIdAndUpdate(
      session._id,
      update,
      { new: true }
    );
    if (!completedSession) {
      throw new ApiError(404, 'Ride session not found');
    }
    await TripSession.findByIdAndUpdate(session.tripSessionId, {
      $inc: { occupancyCount: -1 },
    });
    await StopAlert.updateMany(
      {
        rideSessionId: session._id,
        status: { $in: ['sent', 'seen', 'acknowledged'] },
      },
      {
        $set: {
          status: 'dismissed',
          acknowledgedAt: endedAt,
        },
      }
    );
    const passenger = await Passenger.findById(session.passengerId).select('userId');
    await publishNotification({
      userId: passenger?.userId,
      type: 'ride_completed',
      title: 'Ride completed',
      body:
        req.user.role === PASSENGER
          ? 'Your ride has been marked as unloaded.'
          : 'Your onboard ride session has been completed.',
      payload: {
        rideSessionId: completedSession._id.toString(),
        tripSessionId: completedSession.tripSessionId.toString(),
        previousStatus,
        rideSession: serializeRideSession(completedSession),
      },
      category: 'ride',
    });
    return ok(res, completedSession, 'Ride session completed');
  })
);

module.exports = router;
