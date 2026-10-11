const mongoose = require('mongoose');
const Pickup = require('../models/pickupRequest');
const Passenger = require('../models/passenger');
const Jeepney = require('../models/jeepney');
const Trip = require('../models/tripSession');
const Driver = require('../models/driver');
const { haversineMeters } = require('../utils/geo');
const { validPoint } = require('../utils/destinationArrival');

async function processRequest({ pickupRequest, now = new Date() }) {
  const transaction = await mongoose.startSession();
  let ready = null;
  try {
    await transaction.withTransaction(async () => {
      ready = null;
      const request = await Pickup.findOne({ _id: pickupRequest._id, flowVersion: 2, status: 'pending', expiresAt: { $gt: now } }).session(transaction);
      if (!request) return;
      const trip = await Trip.findOne({ _id: request.tripSessionId, status: 'active' }).session(transaction);
      const passenger = await Passenger.findById(request.passengerId).session(transaction);
      const jeep = trip && await Jeepney.findById(trip.jeepneyId).session(transaction);
      const driver = trip?.driverId && await Driver.findById(trip.driverId).session(transaction);
      const fresh = time => time && now - new Date(time) >= 0 && now - new Date(time) <= 15000;
      const driverAt = jeep?.latestLocationOrder?.capturedAt;
      const prior = request.autoBoarding?.toObject?.() || request.autoBoarding || {};
      const eligible = trip?.flowVersion === 2 && trip.acceptRequests && driver?.status === 'active' && jeep?.status === 'active' && validPoint(passenger?.lastKnownLocation) && validPoint(jeep?.lastKnownLocation) &&
        fresh(passenger.lastSeenAt) && fresh(driverAt) && jeep.latestLocationOrder.streamId && Number.isSafeInteger(jeep.latestLocationOrder.sequence) && jeep.latestLocationOrder.sequence > 0 &&
        (request.pickupType !== 'terminal' || trip.operatingMode === 'terminal_queue' && trip.terminalQueueStatus === 'loading');
      const reject = async reason => {
        request.autoBoarding = { lastCheckedAt: now, lastReason: reason };
        await request.save({ session: transaction });
        if (prior.lastReason !== reason) await require('../models/activityLog').create([{ actorRole: 'system', action: 'gps_boarding_rejected', entity: 'PickupRequest', entityId: String(request._id), details: { reason, tripId: String(request.tripSessionId), memberIds: request.members.map(m => m.memberId), at: now } }], { session: transaction });
      };
      if (!eligible) { await reject('ineligible_trip_or_missing_fresh_gps'); return; }
      const p = passenger.lastKnownLocation.coordinates; const v = jeep.lastKnownLocation.coordinates;
      const near = haversineMeters(p[1], p[0], v[1], v[0]) <= 25;
      if (!near) { await reject('outside_boarding_radius'); return; }
      const continuous = near && prior.streamId === jeep.latestLocationOrder.streamId && prior.tripId === String(trip._id) && prior.proximityStartedAt &&
        prior.lastCheckedAt && now - prior.lastCheckedAt <= 15000;
      const startedAt = near ? continuous ? prior.proximityStartedAt : now : undefined;
      const distinct = continuous && passenger.lastSeenAt > startedAt && driverAt > startedAt;
      request.autoBoarding = { lastReason: 'valid', streamId: jeep.latestLocationOrder.streamId, tripId: String(trip._id), proximityStartedAt: startedAt, lastCheckedAt: now,
        lastPassengerSampleAt: passenger.lastSeenAt, lastDriverSampleAt: driverAt,
        lastDistanceMeters: haversineMeters(p[1], p[0], v[1], v[0]) };
      await request.save({ session: transaction });
      if (continuous && distinct && now - startedAt >= 10000) ready = { request, trip };
    });
  } finally { await transaction.endSession(); }
  if (!ready) return null;
  return require('./boarding.service').completeBoardingForPickupRequest({ pickupRequest: ready.request, trip: ready.trip,
    passengerId: ready.request.passengerId, now, boardingMethod: 'auto_proximity', allowExisting: true });
}
module.exports = { processRequest };
