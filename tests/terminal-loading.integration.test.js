const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');
const Trip = require('../src/models/tripSession');
const Driver = require('../src/models/driver');
const User = require('../src/models/user');
const Jeep = require('../src/models/jeepney');
const Pickup = require('../src/models/pickupRequest');
const Passenger = require('../src/models/passenger');
const Holiday = require('../src/models/codingHoliday');
const Notification = require('../src/models/notification');
const queue = require('../src/services/terminalQueue.service');
const lifecycle = require('../src/services/tripLifecycle.service');
const { manilaDate } = require('../src/services/operatingRules.service');
let repl, trip;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri());
  await Promise.all(Object.values(mongoose.models).map(m => m.init()));
  await Holiday.create({ date: manilaDate(), name: 'Isolated test holiday' });
  const user = await User.create({ email: 'timer@example.test', fullName: 'Timer test', role: 'DRIVER' });
  const driverId = new mongoose.Types.ObjectId();
  await Driver.collection.insertOne({ _id: driverId, userId: user._id, status: 'active' });
  const jeep = await Jeep.create({ plateNumber: 'TEST 123', capacity: 1 });
  trip = await Trip.create({ driverId, jeepneyId: jeep._id, routeId: new mongoose.Types.ObjectId(), status: 'active', operatingMode: 'terminal_queue', terminalQueueStatus: 'waiting' });
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });
const destinationLocation = { type: 'Point', coordinates: [121, 14] };
const reserve = async (pickupType = 'terminal') => {
  const passenger = await Passenger.create({ userId: new mongoose.Types.ObjectId() });
  return lifecycle.createTripRecord(Pickup, { destinationLocation, passengerId: passenger._id, tripSessionId: trip._id, routeId: trip.routeId, pickupType, expiresAt: new Date(Date.now() + 3600000) }, { accepting: true });
};
test('promotion sets timer; concurrent reservations cannot overbook; expiry preserves trip and reservations', async () => {
  await queue.transaction(trip.routeId, session => queue.promote(trip.routeId, session));
  trip = await Trip.findById(trip._id);
  assert.ok(trip.terminalLoadingStartedAt);
  const results = await Promise.allSettled([reserve(), reserve()]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1, results.map(r => r.reason?.message).join('\n'));
  await Trip.updateOne({ _id: trip._id }, { terminalLoadingStartedAt: new Date(Date.now() - 600001) });
  await assert.rejects(reserve(), /10-minute/);
  assert.equal(await Pickup.countDocuments({ tripSessionId: trip._id }), 1);
  assert.equal((await Trip.findById(trip._id)).terminalQueueStatus, 'loading');
  await Trip.updateOne({ _id: trip._id }, { operatingMode: 'route', terminalQueueStatus: 'departed' });
  // Route mode also respects existing reservations. Release the old booking
  // before proving that a new roadside reservation is accepted.
  await assert.rejects(reserve('roadside'), error => error.code === 'INSUFFICIENT_SEATS');
  await Pickup.updateMany({ tripSessionId: trip._id }, { $set: { status: 'cancelled' } });
  await reserve('roadside');
  assert.equal(await Pickup.countDocuments({ tripSessionId: trip._id, pickupType: 'roadside' }), 1);
  await Trip.updateOne({ _id: trip._id }, { operatingMode: 'terminal_queue', terminalQueueStatus: 'loading' });
  await Promise.all([queue.reconcile(), queue.reconcile()]);
  assert.equal(await Notification.countDocuments({ type: 'terminal_loading' }), 1);
  assert.equal((await Trip.findById(trip._id)).terminalQueueStatus, 'loading');
});
