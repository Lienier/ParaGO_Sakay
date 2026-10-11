const mongoose = require('mongoose');
const Pickup = require('../models/pickupRequest');
const Trip = require('../models/tripSession');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const Jeep = require('../models/jeepney');
const ApiError = require('../utils/apiError');
const { haversineMeters } = require('../utils/geo');
const config = require('../config/env');
const { serializePickupRequest } = require('../utils/realtimePayloads');
async function ready(requestId, userId) {
  const session = await mongoose.startSession();
  let booking, driver, changed;
  try { await session.withTransaction(async () => {
    changed = false;
    const passenger = await Passenger.findOne({ userId }).session(session);
    booking = passenger && await Pickup.findOne({ _id: requestId, passengerId: passenger._id }).session(session);
    if (!booking) throw new ApiError(404, 'Booking not found.');
    if (booking.flowVersion === 2) throw new ApiError(409, 'This booking boards automatically. Group-ready confirmation is not needed.', [], 'AUTO_BOARDING_PENDING');
    if ((booking.partySize ?? 1) <= 1) throw new ApiError(409, 'Use the normal boarding action for a solo booking.');
    if (booking.status !== 'acknowledged' || booking.expiresAt <= new Date()) throw new ApiError(409, 'This booking is not ready for boarding. Refresh its status.');
    const trip = await Trip.findOneAndUpdate({ _id: booking.tripSessionId, status: 'active' }, { $inc: { lifecycleRevision: 1 } }, { new: true, session });
    if (!trip || (booking.pickupType === 'terminal' && (trip.operatingMode !== 'terminal_queue' || trip.terminalQueueStatus !== 'loading'))) throw new ApiError(409, 'Your assigned jeep is no longer available for this boarding.');
    const jeep = await Jeep.findById(trip.jeepneyId).session(session);
    const p = passenger.lastKnownLocation?.coordinates, v = jeep?.lastKnownLocation?.coordinates;
    const fresh = (date, max) => date && Date.now() - date >= 0 && Date.now() - date <= max * 1000;
    if (!fresh(passenger.lastSeenAt, config.autoBoardingPassengerLocationMaxAgeSeconds) || !fresh(jeep?.lastSeenAt, config.autoBoardingDriverLocationMaxAgeSeconds) || p?.length !== 2 || v?.length !== 2) throw new ApiError(409, 'Refresh your location near your assigned jeep and try again.', [], 'BOARDING_GPS_REQUIRED');
    if (haversineMeters(p[1], p[0], v[1], v[0]) > config.autoBoardingProximityMeters) throw new ApiError(409, 'Move near your assigned jeep before requesting group boarding.', [], 'BOARDING_TOO_FAR');
    if (booking.groupReadyAt) return;
    booking.groupReadyAt = new Date(); await booking.save({ session });
    driver = await Driver.findById(trip.driverId).session(session); changed = true;
  }); } finally { await session.endSession(); }
  if (changed) {
    try { await require('./notificationPublisher').publishNotification({ userId: driver?.userId,
      type: 'pickup_request_created', category: 'trip', title: 'Confirm group boarding',
      body: `A group of ${booking.partySize} is ready. Confirm the number onboard when safely stopped.`,
      payload: { requestId: String(booking._id), tripSessionId: String(booking.tripSessionId), groupReady: true, request: serializePickupRequest(booking) } });
    } catch (_) { console.error('[Group boarding] Notification failed after commit'); }
  }
  return booking;
}
module.exports = { ready };
