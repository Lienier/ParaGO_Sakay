const mongoose = require('mongoose');
const Ride = require('../models/rideSession');
const Trip = require('../models/tripSession');
const ApiError = require('../utils/apiError');
const { destinationKey, evaluateArrival } = require('../utils/destinationArrival');

function finishMembers(ride, members, { now, method, requestId, actorId, actorRole }) {
  const events = new Map();
  for (const member of members) {
    member.status = 'completed'; member.completedAt = now; member.completionMethod = method;
    const key = destinationKey(member);
    if (!events.has(key)) events.set(key, { requestId: `${requestId}:${key}`, actorId, actorRole, method, at: now,
      count: 0, memberIds: [], destinationStopRef: member.destinationStopRef, destinationLocation: member.destinationLocation,
      revision: ride.revision });
    const event = events.get(key); event.count++; event.memberIds.push(member.memberId);
  }
  ride.remainingCount = ride.members.filter(m => m.status === 'onboard').length;
  ride.revision++;
  for (const event of events.values()) { event.remainingCount = ride.remainingCount; ride.unloadMutations.push(event); }
  if (ride.remainingCount === 0) {
    ride.status = 'completed'; ride.endedAt = now; ride.canSendStopAlert = false;
    ride.offboardingMethod = method; ride.completedByRole = actorRole;
    if (mongoose.isValidObjectId(actorId)) ride.completedByUserId = actorId;
  }
  return members.length;
}
async function publish(ride, released, method) {
  const { publishNotification } = require('./notificationPublisher');
  const { serializeRideSession } = require('../utils/realtimePayloads');
  try {
  const passenger = await require('../models/passenger').findById(ride.passengerId).select('userId');
  const trip = await Trip.findById(ride.tripSessionId).select('driverId');
  const driver = trip?.driverId && await require('../models/driver').findById(trip.driverId).select('userId');
  for (const userId of [passenger?.userId, driver?.userId].filter(Boolean)) {
    try {
      await publishNotification({ userId, type: ride.status === 'completed' ? 'ride_completed' : 'ride_count_updated',
        title: ride.status === 'completed' ? 'Ride completed' : 'Passengers unloaded',
        body: `${released} passenger(s) unloaded. ${ride.remainingCount} remain in this booking.`,
        category: 'ride', payload: { rideSessionId: String(ride._id), tripSessionId: String(ride.tripSessionId),
          completionMethod: method, releasedSeats: released, rideSession: serializeRideSession(ride) } });
    } catch (_) { console.error('[Member unloading] Notification failed after commit'); }
  }
  } catch (_) { console.error('[Member unloading] Notification recipient lookup failed after commit'); }
}
async function processRide({ rideId, observation, now = new Date(), manual = null }) {
  const transaction = await mongoose.startSession();
  let result; let released = 0;
  try {
    await transaction.withTransaction(async () => {
      released = 0;
      const ride = await Ride.findOne({ _id: rideId, flowVersion: 2 }).session(transaction);
      if (!ride) throw new ApiError(404, 'Ride not found');
      result = ride;
      if (manual) {
        const prior = ride.unloadMutations.filter(e => e.requestId.startsWith(`${manual.requestId}:`));
        if (prior.length) {
          const ids = prior.flatMap(e => e.memberIds).sort();
          if (prior.some(e => e.actorId !== manual.actorId) || JSON.stringify(ids) !== JSON.stringify([...(manual.memberIds || [])].sort())) throw new ApiError(409, 'This correction reference was already used for different passengers.');
          return;
        }
        if (ride.revision !== manual.revision) throw new ApiError(409, 'The group changed. Refresh and try again.', [], 'RIDE_REVISION_CONFLICT');
        if (manual.actorRole === 'passenger') {
          if (!await require('../models/passenger').exists({ _id: ride.passengerId, userId: manual.actorId }).session(transaction)) throw new ApiError(403, 'This is not your ride.');
        } else if (manual.actorRole === 'driver') {
          const driver = await require('../models/driver').findOne({ userId: manual.actorId, status: 'active' }).session(transaction);
          if (!driver || !await Trip.exists({ _id: ride.tripSessionId, driverId: driver._id }).session(transaction)) throw new ApiError(403, 'This is not your trip.');
        } else if (manual.actorRole !== 'admin') throw new ApiError(403, 'Manual correction requires a signed-in account.');
      }
      if (ride.status !== 'onboard') return;
      if (!await Trip.exists({ _id: ride.tripSessionId, status: 'active' }).session(transaction)) return;
      let selected;
      if (manual) {
        if (!Array.isArray(manual.memberIds) || !manual.memberIds.length || new Set(manual.memberIds).size !== manual.memberIds.length) throw new ApiError(400, 'Select the passengers who got off.');
        selected = ride.members.filter(m => manual.memberIds.includes(m.memberId) && m.status === 'onboard');
        if (selected.length !== manual.memberIds.length) throw new ApiError(409, 'Some passengers already got off. Refresh.');
      } else {
        const evaluated = evaluateArrival({ members: ride.members, observation, previous: ride.destinationArrival?.toObject?.() || ride.destinationArrival, now });
        ride.destinationArrival = evaluated.state;
        ride.lastAutomationCheck = { at: now, reason: evaluated.reason, streamId: observation?.streamId, sequence: observation?.sequence };
        selected = evaluated.reachedKey ? ride.members.filter(m => m.status === 'onboard' && destinationKey(m) === evaluated.reachedKey) : [];
      }
      if (selected.length) {
        released = finishMembers(ride, selected, { now, method: manual ? 'manual' : 'auto_destination',
          requestId: manual?.requestId || `gps-${observation.streamId}-${observation.sequence}`, actorId: manual?.actorId || 'system', actorRole: manual?.actorRole || 'system' });
        const updated = await Trip.updateOne({ _id: ride.tripSessionId, status: 'active', occupancyCount: { $gte: released } }, { $inc: { occupancyCount: -released, lifecycleRevision: 1 } }, { session: transaction });
        if (updated.modifiedCount !== 1) throw new ApiError(409, 'Seat count needs reconciliation.');
        if (ride.status === 'completed') await require('../models/stopAlert').updateMany({ rideSessionId: ride._id, status: { $in: ['sent', 'seen', 'acknowledged'] } }, { $set: { status: 'dismissed', acknowledgedAt: now } }, { session: transaction });
      }
      await ride.save({ session: transaction });
      if (released) await require('../models/pickupRequest').updateOne({ _id: ride.pickupRequestId, flowVersion: 2 },
        { $set: { members: ride.members.map(m => m.toObject()) } }, { session: transaction });
      if (released || (!manual && ride.lastAutomationCheck.reason !== 'valid' && ride.lastAutomationCheck.reason !== 'repeated')) await require('../models/activityLog').create([{ actorRole: manual?.actorRole || 'system', action: released ? 'member_unloading' : 'gps_unloading_rejected', entity: 'RideSession', entityId: String(ride._id), details: { releasedSeats: released, events: released ? ride.unloadMutations.filter(e => selected.some(m => e.memberIds.includes(m.memberId))).map(e => e.toObject()) : [], gpsCheck: ride.lastAutomationCheck?.toObject?.(), tripId: String(ride.tripSessionId) } }], { session: transaction });
    });
  } finally { await transaction.endSession(); }
  if (released) await publish(result, released, manual ? 'manual' : 'auto_destination');
  return result;
}
async function processTrip({ tripSessionId, observation, now = new Date() }) {
  const rides = await Ride.find({ tripSessionId, flowVersion: 2, status: 'onboard' }).select('_id');
  const completed = [];
  for (const ride of rides) completed.push(await processRide({ rideId: ride._id, observation, now }));
  return completed;
}
module.exports = { processRide, processTrip, finishMembers };
