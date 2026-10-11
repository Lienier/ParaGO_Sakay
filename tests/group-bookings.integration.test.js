const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path'), os = require('node:os');
const Passenger = require('../src/models/passenger'), Driver = require('../src/models/driver');
const User = require('../src/models/user');
const Trip = require('../src/models/tripSession'), Jeep = require('../src/models/jeepney');
const Pickup = require('../src/models/pickupRequest'), Ride = require('../src/models/rideSession');
const Holiday = require('../src/models/codingHoliday');
const { manilaDate } = require('../src/services/operatingRules.service');
const { createTripRecord, endTrip } = require('../src/services/tripLifecycle.service');
const { completeBoardingForPickupRequest: board } = require('../src/services/boarding.service');
const { completeRideSession: unload } = require('../src/services/rideCompletion.service');
const { ready } = require('../src/services/groupBoarding.service');
const point = { type: 'Point', coordinates: [121, 14] };
let repl;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { version: '8.0.28', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri());
  await Promise.all([Pickup.init(), Ride.init()]);
  await Holiday.create({ date: manilaDate(), name: 'Group tests' });
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });
async function fixture(capacity = 6) {
  const passenger = await Passenger.create({ userId: new mongoose.Types.ObjectId(), lastKnownLocation: point, lastSeenAt: new Date() });
  const driverUser = await User.create({ email: `${new mongoose.Types.ObjectId()}@group.test`, fullName: 'Group driver', role: 'DRIVER' });
  const driver = await Driver.create({ userId: driverUser._id, status: 'active' });
  const jeep = await Jeep.create({ plateNumber: `TEST ${Date.now()}1`, capacity, lastKnownLocation: point, lastSeenAt: new Date() });
  const route = await require('../src/models/route').create({ name: 'Group test route', code: String(new mongoose.Types.ObjectId()), status: 'active' });
  const trip = await Trip.create({ driverId: driver._id, jeepneyId: jeep._id, routeId: route._id, status: 'active', operatingMode: 'route', acceptRequests: true });
  return { passenger, driver, jeep, trip };
}
function booking(f, size = 3) { return { passengerId: f.passenger._id, tripSessionId: f.trip._id, routeId: f.trip.routeId,
  pickupType: 'roadside', partySize: size, pickupLocation: point, destinationLocation: point, destinationStopRef: 'End',
  fareSnapshot: { amount: 20 }, status: 'acknowledged', expiresAt: new Date(Date.now() + 600000) }; }
test('simultaneous whole groups reserve at most capacity on roadside trips', async () => {
  const f = await fixture(5);
  const second = await Passenger.create({ userId: new mongoose.Types.ObjectId() });
  const results = await Promise.allSettled([createTripRecord(Pickup, booking(f), { accepting: true }),
    createTripRecord(Pickup, { ...booking(f), passengerId: second._id }, { accepting: true })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(await Pickup.countDocuments({ tripSessionId: f.trip._id }), 1);
});
test('group readiness, driver ownership, partial boarding and unloading remain exactly once', async () => {
  const f = await fixture();
  const pickupRequest = await createTripRecord(Pickup, booking(f, 4), { accepting: true });
  const args = { pickupRequest, trip: f.trip, passengerId: f.passenger._id, boardingMethod: 'manual', allowExisting: true };
  await assert.rejects(board(args), e => e.code === 'GROUP_CONFIRMATION_REQUIRED');
  await assert.rejects(ready(pickupRequest._id, new mongoose.Types.ObjectId()), e => e.statusCode === 404);
  await ready(pickupRequest._id, f.passenger.userId);
  await assert.rejects(board({ ...args, groupConfirmation: { count: 3, requestId: 'board-wrong', driverUserId: new mongoose.Types.ObjectId() } }), e => e.statusCode === 403);
  const groupConfirmation = { count: 3, requestId: 'board-valid', driverUserId: f.driver.userId };
  const [ride, duplicate] = await Promise.all([board({ ...args, groupConfirmation }), board({ ...args, groupConfirmation })]);
  assert.equal(String(ride._id), String(duplicate._id));
  assert.equal(ride.partySize, 4); assert.equal(ride.boardedCount, 3); assert.equal(ride.regularTotal, 60);
  await assert.rejects(board({ ...args, groupConfirmation: { ...groupConfirmation, count: 2, requestId: 'changed-count' } }), e => e.code === 'BOARDING_COUNT_CONFLICT');
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 3);
  assert.equal((await require('../src/services/seatAccounting.service').counts(await Trip.findById(f.trip._id))).reserved, 0);
  await assert.rejects(unload({ session: ride, trip: f.trip, actorRole: 'driver', actorUserId: f.driver.userId }), e => e.code === 'GROUP_ACTION_REQUIRED');
  const action = { session: ride, trip: f.trip, actorRole: 'driver', actorUserId: f.driver.userId,
    groupAction: { count: 1, revision: 0, requestId: 'unload-first' } };
  await Promise.all([unload(action), unload(action)]);
  const partial = await Ride.findById(ride._id);
  assert.equal(partial.remainingCount, 2); assert.equal(partial.status, 'onboard');
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 2);
  await assert.rejects(unload({ ...action, actorRole: 'passenger', actorUserId: new mongoose.Types.ObjectId(), groupAction: { count: 2, revision: 1, requestId: 'wrong-owner' } }), e => e.statusCode === 403);
  await assert.rejects(unload({ ...action, actorRole: 'passenger', actorUserId: f.passenger.userId, groupAction: { count: 1, revision: 1, requestId: 'partial-owner' } }), e => e.statusCode === 400);
  const flow = require('../src/services/passengerFlow.service');
  const range = { from: new Date(Date.now() - 60000), to: new Date(Date.now() + 60000), tripIds: [f.trip._id] };
  assert.equal(await flow.totalSeats(flow.unloadingPipeline(range)), 1, 'partial unload is reported while the ride remains active');
  await assert.rejects(unload({ ...action, groupAction: { count: 1, revision: 0, requestId: 'unload-stale' } }), e => e.code === 'RIDE_REVISION_CONFLICT');
  await unload({ ...action, session: partial, groupAction: { count: 2, revision: 1, requestId: 'unload-final' } });
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
  assert.equal((await Ride.findById(ride._id)).status, 'completed');
  assert.equal(await flow.totalSeats(flow.unloadingPipeline(range)), 3, 'final completion does not count partial unloads twice');
});
test('automatic unloading does not release a group reduced to one; ending trip clears remaining count', async () => {
  const f = await fixture();
  const pickupRequest = await createTripRecord(Pickup, booking(f, 2), { accepting: true });
  await ready(pickupRequest._id, f.passenger.userId);
  const ride = await board({ pickupRequest, trip: f.trip, passengerId: f.passenger._id,
    groupConfirmation: { count: 1, requestId: 'board-single', driverUserId: f.driver.userId } });
  const result = await require('../src/services/automaticOffboarding.service').processAutomaticOffboardingForRide({ ride, trip: f.trip, jeepneyLocation: point });
  assert.equal(result, null);
  // The completion service independently enforces the same safeguard.
  await unload({ session: ride, trip: f.trip, completionMethod: 'auto_separation' });
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 1);
  await endTrip(f.trip._id);
  assert.equal((await Ride.findById(ride._id)).remainingCount, 0);
  const flow = require('../src/services/passengerFlow.service');
  assert.equal(await flow.totalSeats(flow.unloadingPipeline({ from: new Date(Date.now() - 60000), to: new Date(Date.now() + 60000), tripIds: [f.trip._id] })), 1);
});

test('group readiness needs fresh nearby GPS and driver confirmation rechecks it', async () => {
  const f = await fixture();
  const pickupRequest = await createTripRecord(Pickup, booking(f), { accepting: true });
  await Passenger.updateOne({ _id: f.passenger._id }, { $unset: { lastSeenAt: 1 } });
  await assert.rejects(ready(pickupRequest._id, f.passenger.userId), e => e.code === 'BOARDING_GPS_REQUIRED');
  await Passenger.updateOne({ _id: f.passenger._id }, { lastSeenAt: new Date() });
  await ready(pickupRequest._id, f.passenger.userId);
  await Passenger.updateOne({ _id: f.passenger._id }, { lastKnownLocation: { type: 'Point', coordinates: [122, 14] } });
  await assert.rejects(board({ pickupRequest, trip: f.trip, passengerId: f.passenger._id, groupConfirmation: { count: 3, requestId: 'gps-recheck', driverUserId: f.driver.userId } }), e => e.statusCode === 409);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
});

test('terminal transfers reserve the whole group, preserve deadline and fare, and accept once', async () => {
  const queue = require('../src/services/terminalQueue.service');
  const f = await fixture(4);
  await Trip.updateOne({ _id: f.trip._id }, { operatingMode: 'terminal_queue', terminalQueueStatus: 'waiting' });
  await queue.transaction(f.trip.routeId, session => queue.promote(f.trip.routeId, session));
  const original = await createTripRecord(Pickup, { ...booking(f, 3), pickupType: 'terminal' }, { accepting: true });
  const next = await fixture(2);
  await Trip.updateOne({ _id: next.trip._id }, { routeId: f.trip.routeId, operatingMode: 'terminal_queue', terminalQueueStatus: 'waiting', terminalQueueNumber: 2 });
  await queue.change({ tripId: f.trip._id, actor: { _id: f.driver.userId, role: 'DRIVER' }, action: 'depart', requestId: 'group-depart' });
  const offer = await Pickup.findById(original._id);
  assert.equal(offer.status, 'transfer_offered');
  const args = { requestId: offer._id, passengerId: f.passenger._id, offerId: offer.transferOfferId, accept: true };
  await assert.rejects(queue.transfer(args), e => e.code === 'INSUFFICIENT_SEATS');
  assert.equal((await Pickup.findById(original._id)).status, 'transfer_offered');
  await Jeep.updateOne({ _id: next.jeep._id }, { capacity: 4 });
  const results = await Promise.all([queue.transfer(args), queue.transfer(args)]);
  assert.equal(String(results[0].tripSessionId), String(next.trip._id));
  assert.equal(results[0].partySize, 3);
  assert.equal(results[0].expiresAt.getTime(), original.expiresAt.getTime());
  assert.equal(results[0].fareSnapshot.amount, original.fareSnapshot.amount);
  assert.equal((await require('../src/services/seatAccounting.service').counts(await Trip.findById(next.trip._id))).reserved, 3);
});

test('group boarding racing cancellation never leaves a cancelled onboard booking', async () => {
  const f = await fixture(3);
  const pickupRequest = await createTripRecord(Pickup, booking(f, 3), { accepting: true });
  await ready(pickupRequest._id, f.passenger.userId);
  await Promise.allSettled([
    board({ pickupRequest, trip: f.trip, passengerId: f.passenger._id,
      groupConfirmation: { count: 3, requestId: 'cancel-race', driverUserId: f.driver.userId } }),
    Pickup.findOneAndUpdate({ _id: pickupRequest._id, status: { $in: ['pending', 'acknowledged'] } }, { $set: { status: 'cancelled' } }),
  ]);
  const saved = await Pickup.findById(pickupRequest._id);
  const ride = await Ride.findOne({ pickupRequestId: pickupRequest._id });
  assert.ok(['completed', 'cancelled'].includes(saved.status));
  assert.equal(Boolean(ride), saved.status === 'completed');
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, ride ? 3 : 0);
});

test('terminal departure racing group boarding preserves either onboard seats or the transfer offer', async () => {
  const queue = require('../src/services/terminalQueue.service');
  const f = await fixture(3);
  await Trip.updateOne({ _id: f.trip._id }, { operatingMode: 'terminal_queue', terminalQueueStatus: 'waiting' });
  await queue.transaction(f.trip.routeId, session => queue.promote(f.trip.routeId, session));
  const pickupRequest = await createTripRecord(Pickup, { ...booking(f), pickupType: 'terminal' }, { accepting: true });
  await ready(pickupRequest._id, f.passenger.userId);
  const trip = await Trip.findById(f.trip._id);
  const results = await Promise.allSettled([
    board({ pickupRequest, trip, passengerId: f.passenger._id,
      groupConfirmation: { count: 3, requestId: 'depart-board-race', driverUserId: f.driver.userId } }),
    queue.change({ tripId: trip._id, actor: { _id: f.driver.userId, role: 'DRIVER' }, action: 'depart', requestId: 'departure-race' }),
  ]);
  assert.equal(results[1].status, 'fulfilled');
  const saved = await Pickup.findById(pickupRequest._id);
  const ride = await Ride.findOne({ pickupRequestId: pickupRequest._id });
  assert.equal(saved.status, ride ? 'completed' : 'transfer_offered');
  const departed = await Trip.findById(trip._id);
  assert.equal(departed.operatingMode, 'route');
  assert.equal(departed.occupancyCount, ride ? 3 : 0);
});

test('rollback flag preserves group completion and trip end racing partial unload releases remaining seats once', async () => {
  const config = require('../src/config/env');
  const previous = config.groupBookingsEnabled;
  config.groupBookingsEnabled = false;
  try {
    const f = await fixture(3);
    // Represents a group created before rollback; new HTTP creation is separately gated.
    const pickupRequest = await createTripRecord(Pickup, booking(f), { accepting: true });
    await ready(pickupRequest._id, f.passenger.userId);
    const ride = await board({ pickupRequest, trip: f.trip, passengerId: f.passenger._id,
      groupConfirmation: { count: 3, requestId: 'rollback-board', driverUserId: f.driver.userId } });
    const results = await Promise.allSettled([
      unload({ session: ride, trip: f.trip, actorRole: 'driver', actorUserId: f.driver.userId,
        groupAction: { count: 1, revision: 0, requestId: 'end-unload-race' } }),
      endTrip(f.trip._id),
    ]);
    assert.equal(results[1].status, 'fulfilled');
    const completed = await Ride.findById(ride._id);
    assert.equal(completed.status, 'completed');
    assert.equal(completed.remainingCount, 0);
    assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
    const flow = require('../src/services/passengerFlow.service');
    assert.equal(await flow.totalSeats(flow.unloadingPipeline({ from: new Date(Date.now() - 60000), to: new Date(Date.now() + 60000), tripIds: [f.trip._id] })), 3);
  } finally { config.groupBookingsEnabled = previous; }
});
