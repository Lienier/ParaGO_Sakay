const mongoose = require('mongoose');
const Driver = require('../models/driver');
const Passenger = require('../models/passenger');
const RideSession = require('../models/rideSession');
const StopAlert = require('../models/stopAlert');
const TripSession = require('../models/tripSession');
const ApiError = require('../utils/apiError');
const { serializeRideSession } = require('../utils/realtimePayloads');
const { publishNotification } = require('./notificationPublisher');

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

const passengerCompletionBody = ({ actorRole, completionMethod }) => {
  if (completionMethod === 'auto_separation') {
    return 'Your ride was automatically marked as unloaded after you separated from the jeepney.';
  }
  return actorRole === 'passenger'
    ? 'Your ride has been marked as unloaded.'
    : 'Your onboard ride session has been completed.';
};

const driverCompletionBody = ({ completionMethod }) =>
  completionMethod === 'auto_separation'
    ? 'A passenger was automatically marked as unloaded after separating from the jeepney.'
    : 'A passenger closed their ride session from the passenger app.';

const completeRideSession = async ({
  session,
  trip,
  actorRole = 'system',
  actorUserId = null,
  completionMethod = 'manual',
  groupAction = null,
}) => {
  actorRole = String(actorRole).toLowerCase();
  if (session.flowVersion === 2) {
    if (completionMethod === 'auto_separation') return session;
    if (!groupAction?.requestId || !/^[a-zA-Z0-9-]{8,80}$/.test(groupAction.requestId) || !Number.isSafeInteger(groupAction.revision)) throw new ApiError(400, 'Refresh and select passengers for manual correction.');
    return require('./memberUnloading.service').processRide({ rideId: session._id, manual: { ...groupAction, actorId: String(actorUserId), actorRole } });
  }
  const isGroup = (session.partySize ?? 1) > 1;
  if (isGroup && completionMethod === 'auto_separation') return session;
  if (isGroup && (!groupAction || !Number.isSafeInteger(groupAction.revision) ||
      typeof groupAction.requestId !== 'string' || !/^[a-zA-Z0-9-]{8,80}$/.test(groupAction.requestId))) {
    throw new ApiError(409, 'Update the application to confirm the group unloading count.', [], 'GROUP_ACTION_REQUIRED');
  }
  if (session.status === 'completed' && !isGroup) {
    return session;
  }
  if (session.status !== 'onboard' && !isGroup) {
    throw new ApiError(409, 'Only onboard ride sessions can be completed');
  }

  const previousStatus = session.status;
  const endedAt = new Date();
  const completionUpdate = {
    $set: {
      status: 'completed',
      endedAt,
      canSendStopAlert: false,
      offboardingMethod: completionMethod,
      completedByRole: actorRole,
      ...(actorUserId ? { completedByUserId: actorUserId } : {}),
    },
  };
  if (!hasValidGeoPoint(session.destinationLocation)) {
    completionUpdate.$unset = { destinationLocation: 1 };
  }

  let completedSession;
  let changed = false;
  let releasedCount = 1;
  const transaction = await mongoose.startSession();
  try {
    await transaction.withTransaction(async () => {
      changed = false;
      // A transaction callback may run again after a write conflict. Never reuse
      // the partial-unloading update from a previous attempt.
      const update = { ...completionUpdate, $set: { ...completionUpdate.$set } };
      if (actorRole === 'driver') {
        const driver = actorUserId && await Driver.findOne({ userId: actorUserId, status: 'active' }).session(transaction);
        const assigned = driver && await TripSession.findOne({ _id: session.tripSessionId, driverId: driver._id }).session(transaction);
        if (!assigned) throw new ApiError(403, 'You are no longer assigned to this trip');
      }
      const fresh = await RideSession.findById(session._id).session(transaction);
      if (!fresh) throw new ApiError(404, 'Ride not found. Refresh your trip.');
      if (actorRole === 'passenger') {
        const owner = actorUserId && await Passenger.exists({ _id: fresh.passengerId, userId: actorUserId }).session(transaction);
        if (!owner) throw new ApiError(403, 'You can only complete your own ride session');
      }
      if (isGroup) {
        const prior = fresh.unloadMutations.find(m => m.requestId === groupAction.requestId);
        if (prior) {
          if (prior.actorId !== String(actorUserId) || prior.count !== groupAction.count) throw new ApiError(409, 'This action reference was already used. Refresh the ride.');
          completedSession = fresh; return;
        }
        if (fresh.status !== 'onboard' || (fresh.revision ?? 0) !== groupAction.revision) throw new ApiError(409, 'The group count changed. Refresh before confirming unloading.', [], 'RIDE_REVISION_CONFLICT');
        releasedCount = groupAction.count;
        if (!Number.isSafeInteger(releasedCount) || releasedCount < 1 || releasedCount > fresh.remainingCount || (actorRole === 'passenger' && releasedCount !== fresh.remainingCount)) throw new ApiError(400, 'Select a valid unloading count. The organizer must confirm everyone remaining has got off.');
        const remaining = fresh.remainingCount - releasedCount;
        update.$set = { remainingCount: remaining, ...(remaining === 0 ? update.$set : { status: 'onboard' }) };
        update.$inc = { revision: 1 };
        update.$push = { unloadMutations: { requestId: groupAction.requestId, actorId: String(actorUserId), count: releasedCount,
          actorRole, method: completionMethod,
          revision: fresh.revision, remainingCount: remaining, at: endedAt } };
      } else {
        update.$set.remainingCount = 0;
        update.$inc = { revision: 1 };
      }
      completedSession = await RideSession.findOneAndUpdate(
        { _id: session._id, status: 'onboard', ...(isGroup ? { revision: groupAction.revision } : {}) }, update,
        { new: true, session: transaction }
      );
      if (!completedSession) {
        completedSession = await RideSession.findById(session._id).session(transaction);
        if (completedSession?.status !== 'completed') {
          throw new ApiError(409, 'Only onboard ride sessions can be completed');
        }
        return;
      }
      const occupancyChange = await TripSession.updateOne(
        { _id: session.tripSessionId, occupancyCount: { $gte: releasedCount } },
        { $inc: { occupancyCount: -releasedCount } }, { session: transaction }
      );
      if (isGroup && occupancyChange.modifiedCount !== 1) throw new ApiError(409, 'The jeep count needs reconciliation. Refresh and contact support if this continues.');
      if (completedSession.status === 'completed') await StopAlert.updateMany(
        { rideSessionId: session._id, status: { $in: ['sent', 'seen', 'acknowledged'] } },
        { $set: { status: 'dismissed', acknowledgedAt: endedAt } },
        { session: transaction }
      );
      changed = true;
    });
  } finally {
    await transaction.endSession();
  }
  if (!changed) return completedSession;

  try {
    const passenger = await Passenger.findById(session.passengerId).select('userId');
    await publishNotification({
      userId: passenger?.userId,
      type: completedSession.status === 'completed' ? 'ride_completed' : 'ride_count_updated',
      title: completedSession.status === 'completed' ? 'Ride completed' : 'Group count updated',
      body: completedSession.status === 'completed' ? passengerCompletionBody({ actorRole, completionMethod }) : `${completedSession.remainingCount} people remain onboard in your group.`,
      payload: {
        rideSessionId: completedSession._id.toString(),
        tripSessionId: completedSession.tripSessionId.toString(),
        previousStatus,
        completionMethod,
        rideSession: serializeRideSession(completedSession),
      },
      category: 'ride',
    });

  } catch (_) {
    console.error('[Ride completion] Passenger notification failed after commit');
  }

  const shouldNotifyDriver =
    trip?.driverId &&
    (actorRole === 'passenger' || completionMethod === 'auto_separation');
  if (shouldNotifyDriver) {
    try {
      const driver = await Driver.findById(trip.driverId).select('userId');
      await publishNotification({
        userId: driver?.userId,
        type: 'ride_completed',
        title:
          completionMethod === 'auto_separation'
            ? 'Passenger auto-unloaded'
            : 'Passenger unloaded',
        body: driverCompletionBody({ completionMethod }),
        payload: {
          rideSessionId: completedSession._id.toString(),
          tripSessionId: completedSession.tripSessionId.toString(),
          previousStatus,
          completionMethod,
          rideSession: serializeRideSession(completedSession),
        },
        category: 'ride',
      });
    } catch (_) {
      console.error('[Ride completion] Driver notification failed after commit');
    }
  }

  return completedSession;
};

module.exports = { completeRideSession, hasValidGeoPoint };
