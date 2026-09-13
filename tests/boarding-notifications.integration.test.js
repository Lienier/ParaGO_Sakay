const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');
const Trip = require('../src/models/tripSession');
const Driver = require('../src/models/driver');
const Passenger = require('../src/models/passenger');
const Jeep = require('../src/models/jeepney');
const Pickup = require('../src/models/pickupRequest');
const Notification = require('../src/models/notification');
const { completeBoardingForPickupRequest: board } = require('../src/services/boarding.service');
let repl;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri());
  await Promise.all(Object.values(mongoose.models).map(m => m.init()));
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });
for (const boardingMethod of ['manual', 'auto_proximity']) {
  test(`${boardingMethod}: concurrent boarding publishes owner state once and retains driver delivery`, async () => {
    const point = { type: 'Point', coordinates: [121, 14] };
    const passenger = await Passenger.create({ userId: new mongoose.Types.ObjectId(), lastKnownLocation: point, lastSeenAt: new Date() });
    const driver = { _id: new mongoose.Types.ObjectId(), userId: new mongoose.Types.ObjectId() };
    await Driver.collection.insertOne(driver);
    const jeep = await Jeep.create({ plateNumber: boardingMethod, capacity: 2, lastKnownLocation: point, lastSeenAt: new Date() });
    const trip = await Trip.create({ driverId: driver._id, jeepneyId: jeep._id, routeId: new mongoose.Types.ObjectId(), status: 'active', operatingMode: 'route' });
    const pickupRequest = await Pickup.create({ passengerId: passenger._id, tripSessionId: trip._id, routeId: trip.routeId, status: 'acknowledged', pickupLocation: point, destinationLocation: point, destinationStopRef: 'Saved destination', expiresAt: new Date(Date.now() + 600000) });
    const args = { pickupRequest, trip, passengerId: passenger._id, boardingMethod, allowExisting: true };
    const rides = await Promise.all([board(args), board(args)]);
    assert.equal(String(rides[0]._id), String(rides[1]._id));
    assert.equal((await Trip.findById(trip._id)).occupancyCount, 1);
    const notices = await Notification.find({ userId: passenger.userId });
    assert.equal(notices.length, 1);
    assert.equal(notices[0].type, 'pickup_request_completed');
    assert.equal(notices[0].payload.request.status, 'completed');
    assert.equal(notices[0].payload.rideSession.status, 'onboard');
    assert.equal(notices[0].payload.request.passengerId, String(passenger._id));
    assert.equal(await Notification.countDocuments({ userId: driver.userId, type: 'passenger_boarded' }), 1);
  });
}

test('notification storage failure cannot undo boarding or cause retry overcount', async () => {
  const point = { type: 'Point', coordinates: [121, 14] };
  const passenger = await Passenger.create({ userId: new mongoose.Types.ObjectId() });
  const jeep = await Jeep.create({ plateNumber: 'FAIL DELIVERY', capacity: 2 });
  const trip = await Trip.create({ driverId: new mongoose.Types.ObjectId(), jeepneyId: jeep._id, routeId: new mongoose.Types.ObjectId(), status: 'active', operatingMode: 'route' });
  const pickupRequest = await Pickup.create({ passengerId: passenger._id, tripSessionId: trip._id, routeId: trip.routeId, status: 'acknowledged', pickupLocation: point, destinationLocation: point, destinationStopRef: 'Saved destination', expiresAt: new Date(Date.now() + 600000) });
  const original = Notification.create;
  try {
    Notification.create = async () => { throw new Error('Simulated notification outage'); };
    const args = { pickupRequest, trip, passengerId: passenger._id, boardingMethod: 'auto_proximity', allowExisting: true };
    const first = await board(args);
    const retry = await board(args);
    assert.equal(String(first._id), String(retry._id));
    assert.equal((await Trip.findById(trip._id)).occupancyCount, 1);
    assert.equal((await Pickup.findById(pickupRequest._id)).status, 'completed');
  } finally {
    Notification.create = original;
  }
});
