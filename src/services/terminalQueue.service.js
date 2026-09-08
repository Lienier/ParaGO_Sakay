const mongoose = require('mongoose');
const crypto = require('crypto');
const Queue = require('../models/terminalQueue');
const Action = require('../models/terminalQueueAction');
const Trip = require('../models/tripSession');
const Pickup = require('../models/pickupRequest');
const Ride = require('../models/rideSession');
const Driver = require('../models/driver');
const User = require('../models/user');
const Jeepney = require('../models/jeepney');
const ApiError = require('../utils/apiError');
const { invalidateDriverActiveContext } = require('./activeDriverContext.service');
const activeQueue = { status: 'active', operatingMode: 'terminal_queue' };

async function prepare(routeId) {
  try { await Queue.updateOne({ _id: routeId }, { $setOnInsert: { nextPosition: 0, revision: 0 } }, { upsert: true }); }
  catch (error) { if (error.code !== 11000) throw error; }
}
async function lock(routeId, session) {
  const queue = await Queue.findOneAndUpdate({ _id: routeId }, { $inc: { revision: 1 } }, { new: true, session });
  if (!queue) throw new ApiError(503, 'Terminal queue requires initialization');
  return queue;
}
async function eligible(trip, session) {
  const driver = await Driver.findOne({ _id: trip.driverId, status: 'active' }).session(session);
  const user = driver && await User.findOne({ _id: driver.userId, status: 'active' }).session(session);
  const vehicle = await Jeepney.findOne({ _id: trip.jeepneyId, status: 'active' }).session(session);
  return Boolean(user && vehicle && vehicle.capacity > 0);
}
async function sync(trip, session) {
  if (!trip.driverId) return;
  await Driver.updateOne({ _id: trip.driverId }, { $set: {
    operatingMode: trip.operatingMode, terminalQueueStatus: trip.terminalQueueStatus,
    terminalQueueNumber: trip.terminalQueueNumber, terminalCheckedInAt: trip.terminalCheckedInAt,
  } }, { session });
}
async function promote(routeId, session) {
  const loading = await Trip.findOne({ ...activeQueue, routeId, terminalQueueStatus: 'loading' }).session(session);
  if (loading) return loading;
  const waiting = await Trip.find({ ...activeQueue, routeId, terminalQueueStatus: 'waiting' })
    .sort({ terminalQueueNumber: 1 }).session(session);
  for (const trip of waiting) {
    if (!await eligible(trip, session)) continue;
    trip.terminalQueueStatus = 'loading'; trip.acceptRequests = true;
    await trip.save({ session }); await sync(trip, session);
    await Action.create([{ routeId, tripId: trip._id, actorRole: 'SYSTEM', action: 'promote',
      requestId: crypto.randomUUID(), reason: 'First eligible waiting jeep' }], { session });
    return trip;
  }
  return null;
}
async function publish(routeId) {
  const trips = await Trip.find({ routeId, status: 'active' }).select('driverId');
  await Promise.all(trips.map(trip => invalidateDriverActiveContext(trip.driverId)));
  const { emitOperationsChanged } = require('../realtime/socketServer');
  for (const role of ['driver', 'passenger', 'admin']) emitOperationsChanged({ type: 'terminal.queue.updated', routeId: String(routeId), role });
}
async function transaction(routeId, operation) {
  await prepare(routeId);
  const session = await mongoose.startSession();
  let result;
  try { await session.withTransaction(async () => { await lock(routeId, session); result = await operation(session); }); }
  catch (error) {
    if (error.code === 11000) throw new ApiError(409, 'A queue entry or action already exists; refresh the queue');
    throw error;
  } finally { await session.endSession(); }
  try { await publish(routeId); }
  catch (_) { console.error('[Terminal queue] Post-commit update publication failed; clients must refresh'); }
  return result;
}
function validateActor(actor, requestId, reason) {
  if (!actor?._id || !requestId || !/^[a-zA-Z0-9_-]{8,100}$/.test(requestId)) throw new ApiError(400, 'A unique requestId is required');
  if (actor.role === 'ADMIN' && (!reason || !String(reason).trim())) throw new ApiError(400, 'An admin action reason is required');
  if (String(reason || '').length > 500) throw new ApiError(400, 'Reason is too long');
}
async function replay(actor, requestId, action, session) {
  const prior = await Action.findOne({ actorId: actor._id, requestId }).session(session);
  if (prior && prior.action !== action) throw new ApiError(409, 'requestId was used for another action');
  return prior;
}
async function audit(trip, actor, action, requestId, reason, session) {
  await Action.create([{ routeId: trip.routeId, tripId: trip._id, actorId: actor._id, actorRole: actor.role, action, requestId, reason }], { session });
}
async function nextPosition(routeId, session) {
  const max = await Trip.findOne({ routeId, operatingMode: 'terminal_queue', status: { $in: ['active', 'scheduled'] } })
    .sort({ terminalQueueNumber: -1 }).session(session);
  await Queue.updateOne({ _id: routeId }, { $max: { nextPosition: max?.terminalQueueNumber || 0 } }, { session });
  return (await Queue.findOneAndUpdate({ _id: routeId }, { $inc: { nextPosition: 1 } }, { new: true, session })).nextPosition;
}
async function checkIn({ document, actor, requestId, reason, existingId }) {
  validateActor(actor, requestId, reason);
  return transaction(document.routeId, async session => {
    const prior = await replay(actor, requestId, 'check_in', session);
    if (prior) {
      if (String(prior.routeId) !== String(document.routeId)) throw new ApiError(409, 'requestId belongs to another route');
      return Trip.findById(prior.tripId).session(session);
    }
    if (await Trip.exists({ ...activeQueue, $or: [{ driverId: document.driverId }, { jeepneyId: document.jeepneyId }] }).session(session))
      throw new ApiError(409, 'Driver or jeep already has a terminal queue entry');
    const values = { ...document, status: 'active', active: true, operatingMode: 'terminal_queue',
      startedAt: new Date(), terminalCheckedInAt: new Date(), terminalQueueStatus: 'waiting', acceptRequests: false,
      terminalQueueNumber: await nextPosition(document.routeId, session) };
    let trip;
    if (existingId) {
      trip = await Trip.findOneAndUpdate({ _id: existingId, status: 'scheduled' }, { $set: values }, { new: true, session });
      if (!trip) throw new ApiError(409, 'Trip is no longer scheduled');
    } else [trip] = await Trip.create([values], { session });
    if (!await eligible(trip, session)) throw new ApiError(409, 'Driver and jeep must be active');
    await sync(trip, session); await promote(trip.routeId, session);
    await audit(trip, actor, 'check_in', requestId, reason, session);
    return Trip.findById(trip._id).session(session);
  });
}
async function offerTransfers(trip, session) {
  const requests = await Pickup.find({ tripSessionId: trip._id, pickupType: 'terminal',
    status: { $in: ['pending', 'acknowledged'] }, expiresAt: { $gt: new Date() } }).session(session);
  for (const request of requests) {
    request.status = 'transfer_offered'; request.transferOfferId = crypto.randomUUID();
    request.transferFromTripId = trip._id; await request.save({ session });
    const passenger = await require('../models/passenger').findById(request.passengerId).session(session);
    if (passenger?.userId) await require('../models/notification').create([{
      userId: passenger.userId, type: 'terminal_transfer_offered', title: 'Terminal transfer available',
      body: 'Your jeep left the queue. Review a transfer to the loading jeep or cancel your booking.',
      category: 'trip', payload: { requestId: String(request._id), offerId: request.transferOfferId },
    }], { session });
  }
}
async function change({ tripId, actor, action, requestId, reason, direction }) {
  validateActor(actor, requestId, reason);
  const original = await Trip.findById(tripId);
  if (!original) throw new ApiError(404, 'Trip not found');
  return transaction(original.routeId, async session => {
    const prior = await replay(actor, requestId, action, session);
    if (prior) {
      if (String(prior.tripId) !== String(tripId)) throw new ApiError(409, 'requestId belongs to another trip');
      return Trip.findById(tripId).session(session);
    }
    const trip = await Trip.findOne({ _id: tripId, ...activeQueue }).session(session);
    if (!trip) throw new ApiError(409, 'Trip is not in the active terminal queue');
    if (actor.role !== 'ADMIN') {
      const driver = await Driver.findOne({ userId: actor._id }).session(session);
      if (!driver || String(driver._id) !== String(trip.driverId)) throw new ApiError(403, 'This is not your trip');
      if (!['depart', 'skip', 'restore'].includes(action)) throw new ApiError(403, 'Admin action required');
    }
    if (action === 'depart') {
      if (trip.terminalQueueStatus !== 'loading') throw new ApiError(409, 'Only the loading jeep can depart');
      await offerTransfers(trip, session);
      trip.operatingMode = 'route'; trip.terminalQueueStatus = 'departed'; trip.resumedAt = new Date();
      trip.inactivityPausedAt = undefined;
      const vehicle = await Jeepney.findById(trip.jeepneyId).session(session);
      trip.acceptRequests = trip.occupancyCount < vehicle.capacity;
    } else if (action === 'skip' || action === 'restore') {
      if (action === 'skip' && !['waiting', 'loading'].includes(trip.terminalQueueStatus)) throw new ApiError(409, 'This jeep is already skipped');
      if (action === 'restore' && trip.terminalQueueStatus !== 'skipped') throw new ApiError(409, 'Only skipped jeeps can be restored');
      if (action === 'skip') await offerTransfers(trip, session);
      trip.terminalQueueStatus = action === 'skip' ? 'skipped' : 'waiting'; trip.acceptRequests = false;
      trip.terminalQueueNumber = await nextPosition(trip.routeId, session);
    } else if (action === 'reorder') {
      if (trip.terminalQueueStatus !== 'waiting') throw new ApiError(409, 'Only waiting jeeps can be reordered');
      if (!['up', 'down'].includes(direction)) throw new ApiError(400, 'direction must be up or down');
      const waiting = await Trip.find({ ...activeQueue, routeId: trip.routeId, terminalQueueStatus: 'waiting' }).sort({ terminalQueueNumber: 1 }).session(session);
      const index = waiting.findIndex(t => String(t._id) === String(tripId));
      const neighbor = waiting[index + (direction === 'up' ? -1 : 1)];
      if (neighbor) {
        const position = trip.terminalQueueNumber;
        await Trip.updateOne({ _id: trip._id }, { $unset: { terminalQueueNumber: 1 } }, { session });
        trip.terminalQueueNumber = neighbor.terminalQueueNumber; neighbor.terminalQueueNumber = position;
        await neighbor.save({ session }); await sync(neighbor, session);
      }
    } else throw new ApiError(400, 'Unsupported terminal action');
    await trip.save({ session }); await sync(trip, session); await promote(trip.routeId, session);
    await audit(trip, actor, action, requestId, reason, session);
    return Trip.findById(trip._id).session(session);
  });
}
async function reserve(trip, session) {
  if (trip.operatingMode !== 'terminal_queue' || trip.terminalQueueStatus !== 'loading' || !trip.acceptRequests || !await eligible(trip, session))
    throw new ApiError(409, 'This jeep is not loading terminal passengers');
  const vehicle = await Jeepney.findById(trip.jeepneyId).session(session);
  const onboard = await Ride.countDocuments({ tripSessionId: trip._id, status: { $in: ['waiting', 'onboard'] } }).session(session);
  const reserved = await Pickup.countDocuments({ tripSessionId: trip._id, status: { $in: ['pending', 'acknowledged'] }, expiresAt: { $gt: new Date() } }).session(session);
  if (Math.max(trip.occupancyCount || 0, onboard + (trip.manualOccupancyCount || 0)) + reserved >= vehicle.capacity)
    throw new ApiError(409, 'The loading jeep is full. Wait for the next departure');
  // Also conflict with manual occupancy and non-queue lifecycle writes.
  await Trip.updateOne({ _id: trip._id }, { $inc: { lifecycleRevision: 1 } }, { session });
}
async function transfer({ requestId, passengerId, offerId, accept }) {
  const original = await Pickup.findOne({ _id: requestId, passengerId });
  if (!original) throw new ApiError(404, 'Booking not found');
  return transaction(original.routeId, async session => {
    const request = await Pickup.findOne({ _id: requestId, passengerId }).session(session);
    if (!offerId || request.transferOfferId !== offerId) throw new ApiError(409, 'Transfer offer has changed');
    if (accept && request.acceptedTransferOfferId === offerId) return request;
    if (!accept && request.status === 'cancelled') return request;
    if (request.status !== 'transfer_offered' || request.expiresAt <= new Date()) throw new ApiError(409, 'Transfer offer is no longer available');
    if (!accept) request.status = 'cancelled';
    else {
      const trip = await promote(request.routeId, session);
      if (!trip) throw new ApiError(409, 'No loading jeep is available. Your offer remains pending');
      await reserve(trip, session);
      request.tripSessionId = trip._id; request.status = 'pending'; request.acceptedTransferOfferId = offerId;
      request.acknowledgedAt = undefined; request.acknowledgedBy = undefined; request.autoBoarding = undefined;
    }
    await request.save({ session }); return request;
  });
}
async function reconcile() {
  const routes = await Trip.distinct('routeId', { ...activeQueue, terminalQueueStatus: 'waiting' });
  for (const routeId of routes) {
    if (await Trip.exists({ ...activeQueue, routeId, terminalQueueStatus: 'loading' })) continue;
    await transaction(routeId, session => promote(routeId, session));
  }
}
async function describe(value) {
  const trip = value.toObject ? value.toObject() : value;
  if (trip.operatingMode !== 'terminal_queue') return trip;
  const vehicle = await Jeepney.findById(trip.jeepneyId?._id || trip.jeepneyId).select('capacity lastSeenAt');
  const reservedSeats = await Pickup.countDocuments({ tripSessionId: trip._id, status: { $in: ['pending', 'acknowledged'] }, expiresAt: { $gt: new Date() } });
  const occupied = trip.occupancyCount || 0;
  const queuePosition = trip.terminalQueueStatus === 'skipped' ? null : trip.terminalQueueStatus === 'loading' ? 1 : 1 + await Trip.countDocuments({ ...activeQueue, routeId: trip.routeId?._id || trip.routeId,
    $or: [{ terminalQueueStatus: 'loading' }, { terminalQueueStatus: 'waiting', terminalQueueNumber: { $lt: trip.terminalQueueNumber } }] });
  return { ...trip, terminalSummary: { queuePosition, reservedSeats, onboardSeats: occupied,
    availableSeats: Math.max(0, (vehicle?.capacity || 0) - occupied - reservedSeats),
    gpsWarning: !vehicle?.lastSeenAt || Date.now() - vehicle.lastSeenAt.getTime() > 300000,
    lastSeenAt: vehicle?.lastSeenAt || null } };
}
module.exports = { audit, validateActor, reconcile, describe, prepare, lock, promote, publish, transaction, checkIn, change, reserve, transfer, activeQueue };
