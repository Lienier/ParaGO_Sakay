const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const express = require('express');
const request = require('supertest');
const User = require('../src/models/user');
const Driver = require('../src/models/driver');
const Passenger = require('../src/models/passenger');
const Trip = require('../src/models/tripSession');
const Ride = require('../src/models/rideSession');
const Notification = require('../src/models/notification');
const AuthSession = require('../src/models/authSession');
const { signToken } = require('../src/utils/jwt');
const { completeRideSession } = require('../src/services/rideCompletion.service');
const app = express();
app.use(express.json());
app.use('/rides', require('../src/routes/rideSessions.routes'));
app.use((error, req, res, next) => res.status(error.statusCode || 500).json({ message: error.message }));
let repl, driver, trip, rides, token, otherToken, passengerUser;
const login = async user => {
  const sid = crypto.randomUUID();
  await AuthSession.create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  return signToken({ sub: String(user._id), sid, role: user.role });
};
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri());
  const user = await User.create({ email: 'unload-driver@example.test', fullName: 'Driver', role: 'DRIVER' });
  driver = await Driver.create({ userId: user._id, status: 'active' });
  const other = await User.create({ email: 'wrong-driver@example.test', fullName: 'Other driver', role: 'DRIVER' });
  await Driver.create({ userId: other._id, status: 'active' });
  passengerUser = await User.create({ email: 'unload-passenger@example.test', fullName: 'Passenger One', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: passengerUser._id });
  trip = await Trip.create({ driverId: driver._id, routeId: new mongoose.Types.ObjectId(), jeepneyId: new mongoose.Types.ObjectId(), status: 'active', occupancyCount: 2 });
  const savedPoint = { type: 'Point', coordinates: [121, 14] };
  rides = await Ride.create([1, 2].map(() => ({ passengerId: passenger._id, tripSessionId: trip._id, pickupRequestId: new mongoose.Types.ObjectId(), status: 'onboard', boardingLocation: savedPoint, destinationLocation: savedPoint, destinationStopRef: 'Same stop' })));
  await Promise.all(Object.values(mongoose.models).map(m => m.init()));
  token = await login(user); otherToken = await login(other);
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });
test('authorized roster preserves passenger IDs and exposes only display names; wrong driver denied', async () => {
  const response = await request(app).get(`/rides/trip/${trip._id}`).set('Authorization', `Bearer ${token}`).expect(200);
  const roster = response.body.data;
  assert.equal(roster[0].passengerDisplayName, 'Passenger One');
  assert.equal(typeof roster[0].passengerId, 'string');
  assert.ok(!JSON.stringify(roster).includes(passengerUser.email));
  await request(app).get(`/rides/trip/${trip._id}`).set('Authorization', `Bearer ${otherToken}`).expect(403);
  await request(app).patch(`/rides/${rides[0]._id}/complete`).set('Authorization', `Bearer ${otherToken}`).expect(403);
});
test('no GPS or para alert needed; duplicate driver completions release one seat and retain audit', async () => {
  await Promise.all([1, 2].map(() => request(app).patch(`/rides/${rides[0]._id}/complete`).set('Authorization', `Bearer ${token}`).expect(200)));
  const completed = await Ride.findById(rides[0]._id);
  assert.equal(completed.completedByRole, 'driver');
  assert.equal(String(completed.completedByUserId), String(driver.userId));
  assert.equal(completed.offboardingMethod, 'manual');
  assert.equal((await Trip.findById(trip._id)).occupancyCount, 1);
  assert.equal((await Ride.findById(rides[1]._id)).status, 'onboard');
  assert.equal(await Notification.countDocuments({ userId: passengerUser._id, type: 'ride_completed' }), 1);
});
test('manual versus automatic race completes once; stale retry cannot release another seat', async () => {
  await Promise.all([
    request(app).patch(`/rides/${rides[1]._id}/complete`).set('Authorization', `Bearer ${token}`).expect(200),
    completeRideSession({ session: rides[1], trip, completionMethod: 'auto_separation' }),
  ]);
  const first = await Ride.findById(rides[1]._id);
  await completeRideSession({ session: rides[1], trip, completionMethod: 'auto_separation' });
  const after = await Ride.findById(rides[1]._id);
  assert.equal(after.endedAt.toISOString(), first.endedAt.toISOString());
  assert.equal(after.completedByRole, first.completedByRole);
  assert.equal((await Trip.findById(trip._id)).occupancyCount, 0);
  assert.equal(await Notification.countDocuments({ userId: passengerUser._id, type: 'ride_completed' }), 2);
});
test('driver assignment is rechecked inside completion rather than trusting an earlier trip snapshot', async () => {
  const savedPoint = { type: 'Point', coordinates: [121, 14] };
  const ride = await Ride.create({ passengerId: rides[0].passengerId, tripSessionId: trip._id, pickupRequestId: new mongoose.Types.ObjectId(), status: 'onboard', boardingLocation: savedPoint, destinationLocation: savedPoint });
  await Trip.updateOne({ _id: trip._id }, { driverId: new mongoose.Types.ObjectId(), occupancyCount: 1 });
  await assert.rejects(completeRideSession({ session: ride, trip, actorRole: 'driver', actorUserId: driver.userId }), /no longer assigned/);
  assert.equal((await Ride.findById(ride._id)).status, 'onboard');
  assert.equal((await Trip.findById(trip._id)).occupancyCount, 1);
});
