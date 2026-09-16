const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const Release = require('../src/models/mobileRelease');
const Policy = require('../src/models/mobileReleasePolicy');
const publisher = require('../scripts/lib/mobileReleasePublisher.cjs');
const updates = require('../src/services/mobileUpdates.service');
const User = require('../src/models/user');
const Passenger = require('../src/models/passenger');
const Driver = require('../src/models/driver');
const Trip = require('../src/models/tripSession');
const Ride = require('../src/models/rideSession');
const Pickup = require('../src/models/pickupRequest');
let repl;
const record = (app, build) => ({ app, build, version: `1.0.${build}`, packageName: 'test.package', certificate: 'test',
  sha256: 'a'.repeat(64), size: 123, objectKey: `releases/${app}/${build}/test.apk`, url: `https://downloads.sakaygaray.com/releases/${app}/${build}/test.apk` });
const reachable = async () => 123;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { version: '8.0.28', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri('release-test'));
  await publisher.initialize();
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });

test('drafts are hidden; publication stays optional; required policy is separate and reversible', async () => {
  await Release.create(record('driver', 10));
  assert.equal((await updates.catalog('driver')).latest, null);
  await publisher.changePolicy({ app: 'driver', operation: 'publish', build: 10, revision: 0, reason: 'Tested installation' }, reachable);
  let policy = await updates.catalog('driver');
  assert.equal(policy.latest.build, 10);
  assert.equal(policy.minimumBuild, 0);
  await publisher.changePolicy({ app: 'driver', operation: 'require', build: 10, revision: 1, reason: 'Major compatibility change' }, reachable);
  assert.equal((await updates.catalog('driver')).minimumBuild, 10);
  await publisher.changePolicy({ app: 'driver', operation: 'optional', revision: 2, reason: 'Recovery' });
  assert.equal((await updates.catalog('driver')).minimumBuild, 0);
});
test('unavailable downloads, draft mandatory builds and stale policy changes are rejected', async () => {
  await Release.create(record('driver', 11));
  await assert.rejects(publisher.changePolicy({ app: 'driver', operation: 'publish', build: 11, revision: 3, reason: 'Test' }, async () => false), /unavailable/);
  await assert.rejects(publisher.changePolicy({ app: 'driver', operation: 'require', build: 11, revision: 3, reason: 'Test' }, reachable), /publish and test/);
  await assert.rejects(publisher.changePolicy({ app: 'driver', operation: 'optional', revision: 0, reason: 'Stale' }), /policy changed/);
  assert.equal((await Policy.findById('driver')).latestBuild, 10);
});
test('competing publications leave one authoritative policy and one audit action', async () => {
  await Release.create(record('driver', 12));
  const outcomes = await Promise.allSettled([11, 12].map(build => publisher.changePolicy({ app: 'driver', operation: 'publish', build, revision: 3, reason: 'Concurrent' }, reachable)));
  assert.equal(outcomes.filter(o => o.status === 'fulfilled').length, 1);
  assert.equal(await publisher.Audit.countDocuments({ reason: 'Concurrent' }), 1);
});
test('required updates preserve ongoing driver trips and passenger bookings/rides', async () => {
  const user = await User.create({ fullName: 'Release test driver', email: 'driver@release.test', role: 'DRIVER' });
  const driver = await Driver.create({ userId: user._id });
  const policy = await Policy.findById('driver');
  await Policy.updateOne({ _id: 'driver' }, { $set: { minimumBuild: 10 } });
  const trip = await Trip.create({ driverId: driver._id, jeepneyId: new mongoose.Types.ObjectId(), routeId: new mongoose.Types.ObjectId(), status: 'active' });
  const current = await updates.status(user, '9');
  assert.equal(current.required, true); assert.equal(current.deferred, true);
  await Trip.updateOne({ _id: trip._id }, { $set: { status: 'completed' } });
  assert.equal((await updates.status(user, '9')).deferred, false);
  assert.equal((await updates.status(user, String(policy.latestBuild))).required, false);

  const passengerUser = await User.create({ fullName: 'Release test passenger', email: 'passenger@release.test', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: passengerUser._id });
  const point = { type: 'Point', coordinates: [121, 14] };
  const booking = await Pickup.create({ passengerId: passenger._id, tripSessionId: trip._id, routeId: trip.routeId, destinationLocation: point, pickupLocation: point, terminalLocation: point, status: 'pending', expiresAt: new Date(Date.now() + 60000) });
  assert.equal(await updates.hasJourney(passengerUser), true);
  await Pickup.updateOne({ _id: booking._id }, { $set: { status: 'completed' } });
  const ride = await Ride.create({ passengerId: passenger._id, tripSessionId: trip._id, pickupRequestId: booking._id, destinationLocation: point, boardingLocation: point, status: 'onboard' });
  assert.equal(await updates.hasJourney(passengerUser), true);
  await Ride.updateOne({ _id: ride._id }, { $set: { status: 'completed' } });
  assert.equal(await updates.hasJourney(passengerUser), false);
});
test('version gate blocks new journeys, including missing build, but preserves safety endpoints and admins', async () => {
  const request = (url, method = 'POST', build = '9', role = 'DRIVER') => ({ originalUrl: url, method, user: { role }, get: () => build });
  await assert.rejects(updates.enforceNewJourney(request('/api/v1/trips')), e => e.statusCode === 426);
  await assert.rejects(updates.enforceNewJourney(request('/trips', 'POST', undefined)), e => e.statusCode === 426);
  for (const [url, method] of [['/api/v1/trips/abc/end', 'PATCH'], ['/stop-alerts', 'POST'], ['/ride-sessions/abc/complete', 'PATCH'], ['/auth/logout', 'POST'], ['/boarding/validate', 'POST']]) {
    await updates.enforceNewJourney(request(url, method));
  }
  await updates.enforceNewJourney(request('/trips', 'POST', '10'));
  await updates.enforceNewJourney(request('/trips', 'POST', '0', 'ADMIN'));
  assert.equal(updates.buildNumber('invalid'), 0);
});
test('uploader verifies storage checksum and never publishes as a side effect', async () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'release-upload-test-'));
  const file = path.join(folder, 'fake.apk');
  fs.writeFileSync(file, 'controlled-test-bytes');
  let put;
  const client = { send: async command => {
    if (command.constructor.name === 'PutObjectCommand') { put = command.input; return {}; }
    return { ContentLength: put.Body.length, ChecksumSHA256: put.ChecksumSHA256 };
  } };
  try {
    await publisher.upload({ file, app: 'passenger' }, { bucket: 'test', origin: 'https://downloads.sakaygaray.com' }, client,
      () => ({ app: 'passenger', build: 20, version: '2.0', packageName: 'test.package', certificate: 'test' }));
    assert.equal(put.IfNoneMatch, '*');
    assert.equal((await updates.catalog('passenger')).latest, null);
    await assert.rejects(publisher.upload({ file, app: 'passenger' }, { bucket: 'test', origin: 'https://downloads.sakaygaray.com' }, client,
      () => ({ app: 'passenger', build: 20 })), /newer/);
    const broken = { send: async () => ({ ContentLength: 0, ChecksumSHA256: 'wrong' }) };
    await assert.rejects(publisher.upload({ file, app: 'passenger' }, { bucket: 'test', origin: 'https://downloads.sakaygaray.com' }, broken,
      () => ({ app: 'passenger', build: 21 })), /verification failed/);
    assert.equal(await Release.countDocuments({ app: 'passenger', build: 21 }), 0);
    const retry = { send: async command => {
      if (command.constructor.name === 'PutObjectCommand') {
        put = command.input;
        const error = new Error('Previous upload already exists');
        error.name = 'PreconditionFailed'; throw error;
      }
      return { ContentLength: put.Body.length, ChecksumSHA256: put.ChecksumSHA256 };
    } };
    await publisher.upload({ file, app: 'passenger' }, { bucket: 'test', origin: 'https://downloads.sakaygaray.com' }, retry,
      () => ({ app: 'passenger', build: 21, version: '2.1', packageName: 'test.package', certificate: 'test' }));
    assert.equal(await Release.countDocuments({ app: 'passenger', build: 21 }), 1);
  } finally { fs.unlinkSync(file); fs.rmdirSync(folder); }
});

test('HTTP gate retains authentication and returns 426 rather than signing users out', async () => {
  const express = require('express');
  const request = require('supertest');
  const authenticate = require('../src/middlewares/authenticate');
  const AuthSession = require('../src/models/authSession');
  const user = await User.findOne({ email: 'driver@release.test' });
  const sid = require('node:crypto').randomUUID();
  await AuthSession.create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  const token = require('../src/utils/jwt').signToken({ sub: String(user._id), role: user.role, sid });
  const app = express();
  app.use('/mobile-updates', require('../src/routes/mobileUpdates.routes'));
  app.post('/trips', authenticate, (_req, res) => res.json({ accepted: true }));
  app.use((error, _req, res, _next) => res.status(error.statusCode || 500).json({ code: error.code }));
  assert.equal((await request(app).get('/mobile-updates/status')).status, 401);
  const denied = await request(app).post('/trips').set('Authorization', `Bearer ${token}`);
  assert.equal(denied.status, 426);
  assert.equal(denied.body.code, 'APP_UPDATE_REQUIRED');
  assert.equal((await AuthSession.findById(sid)).revokedAt, null);
  assert.equal((await request(app).get('/mobile-updates/status').set('Authorization', `Bearer ${token}`)).status, 200);
  assert.equal((await request(app).post('/trips').set('Authorization', `Bearer ${token}`).set('X-App-Build', '10')).status, 200);
  assert.equal((await request(app).post('/mobile-updates/driver')).status, 404);
});
