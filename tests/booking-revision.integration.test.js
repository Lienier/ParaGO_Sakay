const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'booking-revision-access-test-only';
process.env.JWT_REFRESH_SECRET = 'booking-revision-refresh-test-only';
process.env.REDIS_URL = '';
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');
const request = require('supertest');
const express = require('express');
const User = require('../src/models/user');
const Passenger = require('../src/models/passenger');
const Driver = require('../src/models/driver');
const Jeep = require('../src/models/jeepney');
const Trip = require('../src/models/tripSession');
const Route = require('../src/models/route');
const AuthSession = require('../src/models/authSession');
const Holiday = require('../src/models/codingHoliday');
const { manilaDate } = require('../src/services/operatingRules.service');
const { requireBookingPoint } = require('../src/utils/bookingLocation');
let repl, route, app;
const point = (lat) => ({ type: 'Point', coordinates: [121, lat] });
async function token() {
  const user = await User.create({ email: `${new mongoose.Types.ObjectId()}@revision.test`, fullName: 'Remote passenger', role: 'PASSENGER' });
  await Passenger.create({ userId: user._id });
  const sid = require('node:crypto').randomUUID();
  await AuthSession.create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  return require('../src/utils/jwt').signToken({ sub: String(user._id), role: user.role, sid });
}
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { version: '8.0.28', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri());
  await Holiday.create({ date: manilaDate(), name: 'Test' });
  route = await Route.create({ name: 'Test route', code: 'REMOTE', direction: 'up', path: { type: 'LineString', coordinates: [[121, 14], [121, 14.1]] },
    stops: [{ name: 'Start', order: 0, fare: 0, location: point(14) }, { name: 'End', order: 1, fare: 20, location: point(14.1) }] });
  const user = await User.create({ email: 'driver@revision.test', fullName: 'Driver', role: 'DRIVER' });
  const driver = await Driver.create({ userId: user._id, status: 'active' });
  const jeep = await Jeep.create({ plateNumber: 'TEST 123', capacity: 20, lastKnownLocation: point(14), lastSeenAt: new Date() });
  await Trip.create({ driverId: driver._id, jeepneyId: jeep._id, routeId: route._id, status: 'active', operatingMode: 'route', acceptRequests: true });
  app = express(); app.use(express.json()); app.use('/pickup-requests', require('../src/routes/pickupRequests.routes'));
  app.use((e, _req, res, _next) => res.status(e.statusCode || 500).json({ message: e.message, code: e.code }));
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });
const body = () => ({ routeId: String(route._id), pickupType: 'roadside', pickupLocation: point(14.02), destinationLocation: point(14.08), destinationStopRef: 'End' });
test('remote booking accepts absent GPS and ignores distant phone GPS', async () => {
  for (const extra of [{}, { currentLocation: point(0) }]) {
    const response = await request(app).post('/pickup-requests').set('Authorization', `Bearer ${await token()}`).send({ ...body(), ...extra });
    assert.equal(response.status, 201, JSON.stringify(response.body));
    assert.deepEqual(response.body.data.pickupLocation.coordinates, [121, 14.02]);
  }
});
test('missing, off-route and reversed pins remain rejected', async () => {
  for (const extra of [{ pickupLocation: null }, { pickupLocation: { type: 'Point', coordinates: [120, 14] } }, { destinationLocation: point(14.01) }]) {
    const response = await request(app).post('/pickup-requests').set('Authorization', `Bearer ${await token()}`).send({ ...body(), ...extra });
    assert.equal(response.status, 400, JSON.stringify(response.body));
  }
});
test('coordinates reject null, coercible strings, infinity and arrays of wrong size', () => {
  for (const coordinates of [[null, null], ['121', 14], [Infinity, 14], [121], [121, 14, 0], [181, 14]]) {
    assert.throws(() => requireBookingPoint({ coordinates }, 'pickup'), e => e.code === 'INVALID_BOOKING_PIN');
  }
});

test('group creation is gated while solo remains compatible; invalid sizes are rejected', async () => {
  const config = require('../src/config/env');
  const previous = config.groupBookingsEnabled;
  try {
    config.groupBookingsEnabled = false;
    const disabled = await request(app).post('/pickup-requests').set('Authorization', `Bearer ${await token()}`).send({ ...body(), partySize: 2 });
    assert.equal(disabled.status, 409);
    assert.equal(disabled.body.code, 'GROUP_BOOKINGS_DISABLED');
    config.groupBookingsEnabled = true;
    for (const partySize of [0, -1, 1.5, '2']) {
      const invalid = await request(app).post('/pickup-requests').set('Authorization', `Bearer ${await token()}`).send({ ...body(), partySize });
      assert.equal(invalid.status, 400);
    }
    const created = await request(app).post('/pickup-requests').set('Authorization', `Bearer ${await token()}`).send({ ...body(), partySize: 3 });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    assert.equal(created.body.data.partySize, 3);
    const solo = await request(app).post('/pickup-requests').set('Authorization', `Bearer ${await token()}`).send(body());
    assert.equal(solo.status, 201);
    assert.equal(created.body.data.fareSnapshot.amount, solo.body.data.fareSnapshot.amount, 'group keeps the same per-person fare as a solo booking');
  } finally { config.groupBookingsEnabled = previous; }
});
