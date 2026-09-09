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
  completionMethod = 'manual',
}) => {
  if (session.status === 'completed') {
    return session;
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
      offboardingMethod: completionMethod,
    },
  };
  if (!hasValidGeoPoint(session.destinationLocation)) {
    update.$unset = { destinationLocation: 1 };
  }

  let completedSession;
  let changed = false;
  const transaction = await mongoose.startSession();
  try {
    await transaction.withTransaction(async () => {
      changed = false;
      completedSession = await RideSession.findOneAndUpdate(
        { _id: session._id, status: 'onboard' }, update,
        { new: true, session: transaction }
      );
      if (!completedSession) {
        completedSession = await RideSession.findById(session._id).session(transaction);
        if (completedSession?.status !== 'completed') {
          throw new ApiError(409, 'Only onboard ride sessions can be completed');
        }
        return;
      }
      await TripSession.updateOne(
        { _id: session.tripSessionId, occupancyCount: { $gt: 0 } },
        { $inc: { occupancyCount: -1 } }, { session: transaction }
      );
      await StopAlert.updateMany(
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

  const passenger = await Passenger.findById(session.passengerId).select('userId');
  await publishNotification({
    userId: passenger?.userId,
    type: 'ride_completed',
    title: 'Ride completed',
    body: passengerCompletionBody({ actorRole, completionMethod }),
    payload: {
      rideSessionId: completedSession._id.toString(),
      tripSessionId: completedSession.tripSessionId.toString(),
      previousStatus,
      completionMethod,
      rideSession: serializeRideSession(completedSession),
    },
    category: 'ride',
  });

  const shouldNotifyDriver =
    trip?.driverId &&
    (actorRole === 'passenger' || completionMethod === 'auto_separation');
  if (shouldNotifyDriver) {
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
  }

  return completedSession;
};

module.exports = { completeRideSession, hasValidGeoPoint };
