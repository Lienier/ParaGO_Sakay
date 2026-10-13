const mongoose = require('mongoose');
const operatingRules = require('./operatingRules.service');
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
const { DRIVER_ERROR_CODES, driverError } = require('../utils/driverError');
const { invalidateDriverActiveContext } = require('./activeDriverContext.service');
const activeQueue = { status: 'active', operatingMode: 'terminal_queue' };

async function prepare(routeId) {
  try { await Queue.updateOne({ _id: routeId }, { $setOnInsert: { nextPosition: 0, revision: 0 } }, { upsert: true }); }
  catch (error) { if (error.code !== 11000) throw error; }
}
async function lock(routeId, session) {
  const queue = await Queue.findOneAndUpdate({ _id: routeId }, { $inc: { revision: 1 } }, { new: true, session });
  if (!queue) throw driverError(503, DRIVER_ERROR_CODES.QUEUE_CONFLICT,
    'The terminal queue is not ready yet.', 'Refresh the terminal screen and try again.');
  return queue;
}
async function eligible(trip, session) {
  const driver = await Driver.findOne({ _id: trip.driverId, status: 'active' }).session(session);
  const user = driver && await User.findOne({ _id: driver.userId, status: 'active' }).session(session);
  const vehicle = await Jeepney.findOne({ _id: trip.jeepneyId, status: 'active' }).session(session);
  if (!user || !vehicle || vehicle.capacity <= 0) return false;
  try { await operatingRules.assertVehicleAllowed(vehicle, session); }
  catch (error) { if (error.statusCode === 409) return false; throw error; }
  return true;
}
async function sync(trip, session) {
  if (!trip.driverId) return;
  if (trip.operatingMode === 'route') {
    await Driver.updateOne({ _id: trip.driverId }, {
      $set: { operatingMode: 'route', terminalQueueStatus: 'off_queue' },
      $unset: { terminalQueueNumber: '', terminalCheckedInAt: '', terminalStopRef: '' },
    }, { session });
    return;
  }
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
    trip.terminalLoadingStartedAt = new Date();
    trip.terminalLoadingWarnedAt = undefined; trip.terminalLoadingExpiredAt = undefined;
    await trip.save({ session }); await sync(trip, session);
    await Action.create([{ routeId, tripId: trip._id, actorRole: 'SYSTEM', action: 'promote',
      requestId: crypto.randomUUID(), reason: 'First eligible waiting jeep' }], { session });
    return trip;
  }
  return null;
}
async function publish(routeId) {
  const trips = await Trip.find({ routeId, status: { $in: ['scheduled', 'active'] } }).select('driverId');
  await Promise.all(trips.map(trip => invalidateDriverActiveContext(trip.driverId)));
  const { emitOperationsChanged } = require('../realtime/socketServer');
  for (const role of ['driver', 'passenger', 'admin']) emitOperationsChanged({ type: 'terminal.queue.updated', routeId: String(routeId), role });
}
async function transaction(routeId, operation, { publishChanges = true } = {}) {
  await prepare(routeId);
  const session = await mongoose.startSession();
  let result;
  try { await session.withTransaction(async () => { await lock(routeId, session); result = await operation(session); }); }
  catch (error) {
    if (error.code === 11000) throw driverError(409, DRIVER_ERROR_CODES.QUEUE_CONFLICT,
      'This terminal action was already recorded.', 'Refresh the terminal status before trying again.');
    throw error;
  } finally { await session.endSession(); }
  try { if (publishChanges) await publish(routeId); }
  catch (_) { console.error('[Terminal queue] Post-commit update publication failed; clients must refresh'); }
  return result;
}
function validateActor(actor, requestId, reason) {
  if (!actor?._id || !requestId || !/^[a-zA-Z0-9_-]{8,100}$/.test(requestId)) throw driverError(400, DRIVER_ERROR_CODES.REQUEST_ID_CONFLICT,
    'This action is missing a valid request identifier.', 'Refresh the screen and try again.');
  if (String(reason || '').length > 500) throw driverError(400, 'ADMIN_ACTION_REASON_TOO_LONG',
    'The action reason is too long.', 'Use 500 characters or fewer.');
}
async function replay(actor, requestId, action, session) {
  const prior = await Action.findOne({ actorId: actor._id, requestId }).session(session);
  if (prior && prior.action !== action) throw driverError(409, DRIVER_ERROR_CODES.REQUEST_ID_CONFLICT,
    'This request identifier was already used for a different action.', 'Refresh the status and try again once.');
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
async function checkIn({ document, actor, requestId, reason, existingId, session: existingSession }) {
  validateActor(actor, requestId, reason);
  const operation = async session => {
    const prior = await replay(actor, requestId, 'check_in', session);
    if (prior) {
      if (String(prior.routeId) !== String(document.routeId)) throw driverError(409, DRIVER_ERROR_CODES.REQUEST_ID_CONFLICT,
        'This request identifier belongs to another route.', 'Refresh the route status and try again.');
      return Trip.findById(prior.tripId).session(session);
    }
    if (await Trip.exists({ ...activeQueue, $or: [{ driverId: document.driverId }, { jeepneyId: document.jeepneyId }] }).session(session))
      throw driverError(409, DRIVER_ERROR_CODES.QUEUE_CONFLICT,
        'This driver or jeepney already has an active terminal trip.', 'Refresh your trips and use the existing terminal trip.');
    const values = { ...document, flowVersion: require('../config/env').automaticGroupFlowEnabled ? 2 : document.flowVersion || 1, status: 'active', active: true, operatingMode: 'terminal_queue',
      startedAt: new Date(), terminalCheckedInAt: new Date(), terminalQueueStatus: 'waiting', acceptRequests: false,
      terminalQueueNumber: await nextPosition(document.routeId, session) };
    await operatingRules.assertVehicleAllowed(await Jeepney.findById(document.jeepneyId).session(session), session);
    let trip;
    if (existingId) {
      trip = await Trip.findOneAndUpdate({ _id: existingId, status: 'scheduled' }, { $set: values }, { new: true, session });
      if (!trip) throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'This terminal trip is no longer awaiting arrival.', 'Refresh the terminal status before continuing.');
    } else [trip] = await Trip.create([values], { session });
    if (!await eligible(trip, session)) throw driverError(409, DRIVER_ERROR_CODES.DRIVER_OFFLINE,
      'The driver account or jeepney is not eligible for terminal loading.', 'Make sure the account and jeepney are active, then refresh.');
    await sync(trip, session); await promote(trip.routeId, session);
    await audit(trip, actor, 'check_in', requestId, reason, session);
    return Trip.findById(trip._id).session(session);
  };
  return existingSession ? operation(existingSession) : transaction(document.routeId, operation);
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
async function cancel({ tripId, actor, requestId, reason = '' }) {
  validateActor(actor, requestId, reason);
  const original = await Trip.findById(tripId);
  if (!original) throw driverError(404, 'TRIP_NOT_FOUND', 'Trip not found.', 'Refresh your trip.');
  let cancelledPickups = [];
  const result = await transaction(original.routeId, async session => {
    cancelledPickups = [];
    const driverFilter = actor.role === 'ADMIN'
      ? (original.driverId ? { _id: original.driverId } : null) : { userId: actor._id };
    const driver = driverFilter ? await Driver.findOneAndUpdate(driverFilter,
      { $set: { updatedAt: new Date() } }, { new: true, session }) : null;
    if (actor.role !== 'ADMIN' && (!driver || String(driver._id) !== String(original.driverId))) {
      throw driverError(403, DRIVER_ERROR_CODES.TRIP_NOT_ASSIGNED, 'This queue belongs to another driver.', 'Open your own trip.');
    }
    const prior = await replay(actor, requestId, 'cancel_queue', session);
    if (prior && String(prior.tripId) !== String(tripId)) throw driverError(409, DRIVER_ERROR_CODES.REQUEST_ID_CONFLICT,
      'This request belongs to another trip.', 'Refresh and try again.');
    if (prior) return Trip.findById(tripId).session(session);
    let trip = await Trip.findOneAndUpdate({ _id: tripId, operatingMode: 'terminal_queue', status: { $in: ['scheduled', 'active'] } },
      { $inc: { lifecycleRevision: 1 } }, { new: true, session });
    if (!trip) {
      trip = await Trip.findById(tripId).session(session);
      if (trip?.status === 'cancelled' && trip.operatingMode === 'terminal_queue') return trip;
      throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE, 'This trip is no longer queued.', 'Refresh your trip.');
    }
    const seats = await require('./seatAccounting.service').counts(trip, session);
    if (seats.occupied > 0) throw driverError(409, 'QUEUE_HAS_PASSENGERS',
      'Passengers are still onboard.', 'Depart or unload passengers before cancelling the queue.');
    const pickups = await Pickup.find({ tripSessionId: tripId, status: { $in: ['pending', 'acknowledged', 'transfer_offered'] } }).session(session);
    cancelledPickups = pickups.map(pickup => ({ id: pickup._id, passengerId: pickup.passengerId }));
    await Pickup.updateMany({ tripSessionId: tripId, flowVersion: 2, status: { $in: ['pending', 'acknowledged', 'transfer_offered'] } },
      { $set: { status: 'cancelled', 'members.$[].status': 'cancelled' } }, { session });
    await Pickup.updateMany({ tripSessionId: tripId, flowVersion: { $ne: 2 }, status: { $in: ['pending', 'acknowledged', 'transfer_offered'] } },
      { $set: { status: 'cancelled' } }, { session });
    trip.status = 'cancelled'; trip.endedAt = new Date(); trip.active = false; trip.acceptRequests = false;
    trip.terminalQueueStatus = 'off_queue';
    for (const field of ['terminalQueueNumber', 'terminalCheckedInAt', 'terminalLoadingStartedAt', 'terminalLoadingWarnedAt',
      'terminalLoadingExpiredAt', 'terminalStopRef', 'terminalLocation', 'terminalArrivalLastAt', 'terminalArrivalLastStreamId',
      'terminalArrivalLastSequence', 'automaticDepartureCheck', 'automaticFinishCheck']) trip[field] = undefined;
    trip.terminalArrivalFixCount = 0;
    await trip.save({ session });
    if (driver) await Driver.updateOne({ _id: driver._id }, {
      $set: { operatingMode: 'route', terminalQueueStatus: 'off_queue', automaticJourneyPaused: true, automaticJourneyCheck: { observations: 0 } },
      $unset: { terminalQueueNumber: '', terminalCheckedInAt: '', terminalStopRef: '' },
    }, { session });
    await promote(trip.routeId, session);
    await audit(trip, actor, 'cancel_queue', requestId, reason, session);
    return trip;
  });
  await invalidateDriverActiveContext(result.driverId);
  for (const pickup of cancelledPickups) {
    try {
      const passenger = await require('../models/passenger').findById(pickup.passengerId).select('userId');
      const request = await Pickup.findById(pickup.id);
      await require('./notificationPublisher').publishNotification({ userId: passenger?.userId, type: 'pickup_request_cancelled',
        title: 'Booking cancelled', body: 'The jeep left the queue. Please book another jeep.', category: 'trip',
        payload: { requestId: String(pickup.id), request: require('../utils/realtimePayloads').serializePickupRequest(request),
          tripSessionId: String(tripId), routeId: String(original.routeId), reason: 'queue_cancelled' } });
    } catch (_) { console.error('[Terminal queue] Cancellation notification failed after commit'); }
  }
  return result;
}
async function change({ tripId, actor, action, requestId, reason, direction }) {
  validateActor(actor, requestId, reason);
  const original = await Trip.findById(tripId);
  if (!original) throw driverError(404, 'TRIP_NOT_FOUND', 'The selected trip could not be found.', 'Refresh the trip list.');
  return transaction(original.routeId, async session => {
    const prior = await replay(actor, requestId, action, session);
    if (prior) {
      if (String(prior.tripId) !== String(tripId)) throw driverError(409, DRIVER_ERROR_CODES.REQUEST_ID_CONFLICT,
        'This request identifier belongs to another trip.', 'Refresh the terminal status and try again once.');
      return Trip.findById(tripId).session(session);
    }
    const trip = await Trip.findOne({ _id: tripId, ...activeQueue }).session(session);
    if (!trip) throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
      'This trip is no longer in the active terminal queue.', 'Refresh the terminal status to see the current state.');
    if (actor.role !== 'ADMIN') {
      const driver = await Driver.findOne({ userId: actor._id }).session(session);
      if (!driver || String(driver._id) !== String(trip.driverId)) throw driverError(403, DRIVER_ERROR_CODES.TRIP_NOT_ASSIGNED,
        'This trip is assigned to a different driver.', 'Open your assigned trip before trying again.');
      if (!['depart', 'skip', 'restore'].includes(action)) throw driverError(403, 'ADMIN_ACTION_REQUIRED',
        'This terminal action is available only to an administrator.', 'Use the driver actions shown for your trip.');
    }
    if (action === 'depart') {
      if (trip.terminalQueueStatus !== 'loading') throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'This jeepney is not the terminal loading jeep yet.', 'Wait until loading is assigned, then depart from the terminal.');
      await operatingRules.assertVehicleAllowed(await Jeepney.findById(trip.jeepneyId).session(session), session);
      await offerTransfers(trip, session);
      trip.operatingMode = 'route'; trip.terminalQueueStatus = 'departed'; trip.resumedAt = new Date();
      trip.inactivityPausedAt = undefined;
      // Queue metadata is only meaningful while the trip is in terminal mode.
      // Keep the departed status for audit/history, but remove active queue state
      // so driver and admin consumers cannot mistake this trip for a queued one.
      trip.terminalQueueNumber = undefined;
      trip.terminalCheckedInAt = undefined;
      trip.terminalLoadingStartedAt = undefined;
      trip.terminalLoadingWarnedAt = undefined;
      trip.terminalLoadingExpiredAt = undefined;
      trip.terminalStopRef = undefined;
      trip.terminalLocation = undefined;
      trip.terminalArrivalFixCount = 0;
      trip.terminalArrivalLastAt = undefined;
      trip.terminalArrivalLastStreamId = undefined;
      trip.terminalArrivalLastSequence = undefined;
      const vehicle = await Jeepney.findById(trip.jeepneyId).session(session);
      trip.acceptRequests = trip.occupancyCount < vehicle.capacity;
    } else if (action === 'remove') {
      if (actor.role !== 'ADMIN') throw driverError(403, 'ADMIN_ACTION_REQUIRED',
        'Only an administrator can remove a skipped jeepney from terminal dispatch.',
        'Ask an administrator to remove this driver from the terminal queue.');
      if (trip.terminalQueueStatus !== 'skipped') throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'Only a skipped jeepney can be removed from terminal dispatch.',
        'Skip the jeepney first or refresh the terminal status.');
      // Removing a skipped terminal intent ends only this terminal trip. It
      // does not delete the driver, jeepney, bookings, or historical records.
      // Any pending terminal requests already received a transfer offer when
      // the trip was skipped.
      trip.status = 'cancelled';
      trip.active = false;
      trip.acceptRequests = false;
      trip.terminalQueueStatus = 'off_queue';
      trip.terminalQueueNumber = undefined;
      trip.terminalCheckedInAt = undefined;
      trip.terminalLoadingStartedAt = undefined;
      trip.terminalLoadingWarnedAt = undefined;
      trip.terminalLoadingExpiredAt = undefined;
      trip.terminalStopRef = undefined;
      trip.terminalLocation = undefined;
      trip.terminalArrivalFixCount = 0;
    } else if (action === 'skip' || action === 'restore') {
      if (action === 'skip' && !['waiting', 'loading'].includes(trip.terminalQueueStatus)) throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'This jeepney cannot be skipped from its current terminal state.', 'Refresh the queue and follow the available action.');
      if (action === 'restore' && trip.terminalQueueStatus !== 'skipped') throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'Only a skipped jeepney can return to the terminal queue.', 'Refresh the queue to see the current state.');
      if (action === 'skip') await offerTransfers(trip, session);
      trip.terminalQueueStatus = action === 'skip' ? 'skipped' : 'waiting'; trip.acceptRequests = false;
      trip.terminalQueueNumber = await nextPosition(trip.routeId, session);
    } else if (action === 'reorder') {
      if (trip.terminalQueueStatus !== 'waiting') throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
        'Only a waiting jeepney can change queue position.', 'Refresh the terminal queue first.');
      if (!['up', 'down'].includes(direction)) throw driverError(400, 'INVALID_QUEUE_DIRECTION',
        'The queue direction is invalid.', 'Refresh the terminal queue and try again.');
      const waiting = await Trip.find({ ...activeQueue, routeId: trip.routeId, terminalQueueStatus: 'waiting' }).sort({ terminalQueueNumber: 1 }).session(session);
      const index = waiting.findIndex(t => String(t._id) === String(tripId));
      const neighbor = waiting[index + (direction === 'up' ? -1 : 1)];
      if (neighbor) {
        const position = trip.terminalQueueNumber;
        await Trip.updateOne({ _id: trip._id }, { $unset: { terminalQueueNumber: 1 } }, { session });
        trip.terminalQueueNumber = neighbor.terminalQueueNumber; neighbor.terminalQueueNumber = position;
        await neighbor.save({ session }); await sync(neighbor, session);
      }
    } else throw driverError(400, 'UNSUPPORTED_TERMINAL_ACTION',
      'This terminal action is not available.', 'Refresh the terminal status and use the displayed action.');
    await trip.save({ session }); await sync(trip, session); await promote(trip.routeId, session);
    await audit(trip, actor, action, requestId, reason, session);
    return Trip.findById(trip._id).session(session);
  });
}
async function reserve(trip, session, size = 1) {
  if (operatingRules.loadingTiming(trip).departureRequired)
    throw driverError(409, DRIVER_ERROR_CODES.DEPARTURE_REQUIRED,
      'The 10-minute terminal loading period has ended.', 'Confirm departure; the next jeep will load new terminal reservations.');
  if (trip.operatingMode !== 'terminal_queue' || trip.terminalQueueStatus !== 'loading' || !trip.acceptRequests || !await eligible(trip, session))
    throw driverError(409, DRIVER_ERROR_CODES.WRONG_QUEUE_STATE,
      'This jeepney is not currently loading terminal passengers.', 'Refresh the terminal queue and select the loading jeepney.');
  await require('./seatAccounting.service').assertCapacity(trip, size, session);
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
      const journey = require('./passengerJourney.service');
      await journey.lockPassenger(passengerId, session);
      await journey.assertCanBook(passengerId, session, request._id);
      const trip = await promote(request.routeId, session);
      if (!trip) throw new ApiError(409, 'No loading jeep is available. Your offer remains pending');
      if (request.flowVersion === 2 && trip.flowVersion !== 2) throw new ApiError(409, 'Wait for a loading jeep running the updated booking flow. Your offer remains pending.');
      await reserve(trip, session, request.partySize ?? 1);
      request.tripSessionId = trip._id; request.status = 'pending'; request.acceptedTransferOfferId = offerId;
      request.acknowledgedAt = undefined; request.acknowledgedBy = undefined; request.autoBoarding = undefined;
      request.groupReadyAt = undefined;
    }
    await request.save({ session }); return request;
  });
}
async function reconcile() {
  const loadingTrips = await Trip.find({ ...activeQueue, terminalQueueStatus: 'loading' }).select('_id routeId');
  for (const entry of loadingTrips) {
    const changed = await transaction(entry.routeId, async session => {
      const trip = await Trip.findOne({ _id: entry._id, ...activeQueue, terminalQueueStatus: 'loading' }).session(session);
      if (!trip) return false;
      const timing = operatingRules.loadingTiming(trip);
      const field = timing.departureRequired ? 'terminalLoadingExpiredAt' : timing.loadingWarning ? 'terminalLoadingWarnedAt' : null;
      if (!field || trip[field]) return false;
      trip[field] = new Date();
      await trip.save({ session });
      const driver = await Driver.findById(trip.driverId).session(session);
      const admins = await User.find({ role: 'ADMIN', status: 'active' }).select('_id').session(session);
      const recipients = [...new Set([driver?.userId, ...admins.map(u => u._id)].filter(Boolean).map(String))];
      const title = timing.departureRequired ? 'Terminal departure required' : 'Terminal departure approaching';
      const body = timing.departureRequired ? 'The loading period has ended. New terminal reservations are closed. Confirm departure when the jeep leaves.' : 'Two minutes remain in this jeep’s loading period. Prepare for departure.';
      if (recipients.length) await require('../models/notification').create(recipients.map(userId => ({ userId, type: 'terminal_loading', title, body, category: 'trip', payload: { tripId: String(trip._id), routeId: String(trip.routeId) } })), { session });
      return true;
    });
    if (changed) await publish(entry.routeId);
  }
  const routes = await Trip.distinct('routeId', { ...activeQueue, terminalQueueStatus: 'waiting' });
  for (const routeId of routes) {
    if (await Trip.exists({ ...activeQueue, routeId, terminalQueueStatus: 'loading' })) continue;
    await transaction(routeId, session => promote(routeId, session));
  }
}

function driverStatusFor(trip) {
  if (trip.status === 'completed') {
    return { state: 'completed', label: 'Completed', detail: 'This trip has ended.', nextAction: null };
  }
  if (trip.status === 'cancelled') {
    return { state: 'cancelled', label: 'Cancelled', detail: 'This trip is no longer operating.', nextAction: null };
  }
  if (trip.operatingMode === 'route' || trip.terminalQueueStatus === 'departed') {
    return { state: 'on_route', label: 'On route', detail: 'Terminal departure is complete.', nextAction: trip.status === 'active' ? (trip.flowVersion === 2 ? 'Boarding and drop-offs are automatic. Follow the route; use manual corrections only when needed.' : 'Accept pickup requests or end the trip.') : null };
  }
  if (trip.terminalQueueStatus === 'loading') {
    return { state: 'loading', label: 'Loading', detail: 'Passengers may board during the terminal loading period.', nextAction: trip.flowVersion === 2 && require('../config/env').automaticDriverLifecycleEnabled ? 'Departure is detected automatically when the jeep leaves the terminal. Manual controls are available as a fallback.' : 'Confirm departure when loading is complete.' };
  }
  if (trip.terminalQueueStatus === 'waiting') {
    return { state: 'waiting', label: 'Waiting in terminal queue', detail: 'Your jeepney is waiting for its loading turn.', nextAction: 'Wait for the loading position.' };
  }
  if (trip.terminalQueueStatus === 'skipped') {
    return { state: 'waiting', label: 'Skipped in terminal queue', detail: 'This jeepney is not currently loading.', nextAction: 'Restore the jeepney when it is ready to rejoin.' };
  }
  return { state: 'driving_to_terminal', label: 'Driving to terminal', detail: 'Fresh GPS arrival checks you into the terminal automatically.', nextAction: 'Drive to the configured departure terminal.' };
}
const arrivalCodeFor = status => ({
  no_ordered_update: 'TERMINAL_ARRIVAL_PENDING',
  stale_location: DRIVER_ERROR_CODES.GPS_STALE,
  poor_accuracy: DRIVER_ERROR_CODES.GPS_POOR_ACCURACY,
  invalid_coordinates: 'TERMINAL_GPS_INVALID',
  outside_terminal_radius: DRIVER_ERROR_CODES.OUTSIDE_TERMINAL_RADIUS,
  insufficient_valid_fixes: DRIVER_ERROR_CODES.TERMINAL_ARRIVAL_PENDING,
  accepted: 'TERMINAL_ARRIVAL_ACCEPTED',
}[status] || 'TERMINAL_ARRIVAL_PENDING');
async function describe(value) {
  const trip = value.toObject ? value.toObject() : value;
  const driverStatus = driverStatusFor(trip);
  if (trip.operatingMode !== 'terminal_queue') {
    const vehicle = await Jeepney.findById(trip.jeepneyId?._id || trip.jeepneyId).select('capacity');
    const seats = await require('./seatAccounting.service').counts(trip);
    return { ...trip, driverStatus, availableSeats: Math.max(0, (vehicle?.capacity || 0) - seats.occupied - seats.reserved) };
  }
  const vehicle = await Jeepney.findById(trip.jeepneyId?._id || trip.jeepneyId).select('capacity lastSeenAt lastKnownLocation latestLocationOrder');
  const { reserved: reservedSeats, occupied } = await require('./seatAccounting.service').counts(trip);
  const bookings = await Pickup.find({ tripSessionId: trip._id, status: { $in: ['pending', 'acknowledged'] }, expiresAt: { $gt: new Date() } }).select('partySize').lean();
  const routeStops = Array.isArray(trip.routeId?.stops) ? [...trip.routeId.stops] : [];
  routeStops.sort((left, right) => Number(left?.order || 0) - Number(right?.order || 0));
  const endTerminal = routeStops.length ? routeStops[routeStops.length - 1] : null;
  const queuePosition = trip.status !== 'active' || trip.terminalQueueStatus === 'off_queue' ? null : trip.terminalQueueStatus === 'skipped' ? null : trip.terminalQueueStatus === 'loading' ? 1 : 1 + await Trip.countDocuments({ ...activeQueue, routeId: trip.routeId?._id || trip.routeId,
    $or: [{ terminalQueueStatus: 'loading' }, { terminalQueueStatus: 'waiting', terminalQueueNumber: { $lt: trip.terminalQueueNumber } }] });
  return { ...trip, driverStatus, terminalSummary: { queuePosition, reservedSeats, onboardSeats: occupied,
    reservationCount: bookings.length, reservationPartySizes: bookings.map(booking => booking.partySize ?? 1),
    ...operatingRules.loadingTiming(trip),
    availableSeats: Math.max(0, (vehicle?.capacity || 0) - occupied - reservedSeats),
    gpsWarning: !vehicle?.lastSeenAt || Date.now() - vehicle.lastSeenAt.getTime() > 300000,
    lastSeenAt: vehicle?.lastSeenAt || null,
    terminalArrival: {
      status: trip.terminalArrivalStatus || 'no_ordered_update',
      code: arrivalCodeFor(trip.terminalArrivalStatus || 'no_ordered_update'),
      reason: trip.terminalArrivalReason || 'Driver has not provided an ordered location update',
      distanceMeters: trip.terminalArrivalLastDistanceMeters ?? null,
      accuracyMeters: trip.terminalArrivalLastAccuracyMeters ?? null,
      validFixes: Number(trip.terminalArrivalFixCount || 0),
      requiredValidFixes: 2,
      lastUpdateAt: trip.terminalArrivalLastAt || null,
      terminalLocation: trip.terminalLocation || null,
      terminalRadiusMeters: trip.terminalRadiusMeters || null,
      endTerminal: endTerminal
        ? { name: endTerminal.name || endTerminal.code || 'Route end', location: endTerminal.location || null }
        : null,
    },
  } };
}
module.exports = { audit, validateActor, reconcile, describe, driverStatusFor, prepare, lock, promote, publish, transaction, checkIn, change, cancel, reserve, transfer, activeQueue };
