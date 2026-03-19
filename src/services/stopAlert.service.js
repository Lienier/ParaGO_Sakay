const ApiError = require('../utils/apiError');
const StopAlert = require('../models/stopAlert');
const RideSession = require('../models/rideSession');
const TripSession = require('../models/tripSession');
const { stopAlertCooldownMinutes } = require('../config/env');

const createStopAlert = async ({
  passengerId,
  tripSessionId,
  stopRef,
  note,
  location,
}) => {
  const session = await RideSession.findOne({
    passengerId,
    tripSessionId,
    status: 'onboard',
    canSendStopAlert: true,
  });
  if (!session) {
    throw new ApiError(403, 'No onboard verified ride session for stop alert');
  }

  const recent = await StopAlert.findOne({
    passengerId,
    tripSessionId,
    status: 'sent',
    createdAt: { $gte: new Date(Date.now() - stopAlertCooldownMinutes * 60 * 1000) },
  });
  if (recent) {
    throw new ApiError(429, 'Please wait before sending another stop alert');
  }

  const trip = await TripSession.findById(tripSessionId).select('routeId');
  if (!trip) throw new ApiError(404, 'Trip session not found');
  if (trip.status !== 'active') {
    throw new ApiError(409, 'Trip session is not active');
  }

  return StopAlert.create({
    passengerId,
    tripSessionId,
    rideSessionId: session._id,
    routeId: trip.routeId,
    stopRef,
    note,
    location,
    status: 'sent',
  });
};

module.exports = { createStopAlert };
