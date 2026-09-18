const express = require('express');
const RideSession = require('../models/rideSession');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const { ensureObjectId } = require('../utils/validators');
const { completeRideSession } = require('../services/rideCompletion.service');
const {
  requireCurrentPassenger,
  requireTrip,
  requireRideSession,
  ensureDriverAssignedToTrip,
  ensurePassengerOwnsRideSession,
} = require('../services/routeContext.service');

const router = express.Router();

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
    const passengers = await require('../models/passenger').find({
      _id: { $in: sessions.map(ride => ride.passengerId) },
    }).select('userId').populate({ path: 'userId', select: 'fullName' });
    const names = new Map(passengers.map(passenger => [String(passenger._id), passenger.userId?.fullName || null]));
    return ok(res, sessions.map(ride => ({ ...ride.toObject(),
      passengerDisplayName: names.get(String(ride.passengerId)) || null,
    })), 'Trip ride sessions');
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
    if (session.status === 'completed' && (session.partySize ?? 1) === 1) {
      return ok(res, session, 'Ride session already completed');
    }
    const completedSession = await completeRideSession({
      session,
      trip,
      actorRole: req.user.role,
      actorUserId: req.user._id,
      completionMethod: 'manual',
      groupAction: (session.partySize ?? 1) > 1 ? {
        count: req.body.count, requestId: req.body.requestId, revision: req.body.revision,
      } : null,
    });
    return ok(res, completedSession, completedSession.status === 'completed' ? 'Ride session completed' : 'Group passenger count updated');
  })
);

module.exports = router;
