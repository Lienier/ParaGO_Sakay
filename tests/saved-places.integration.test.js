const { test, before, after } = require('node:test');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'saved-places-test-access-secret-only';
process.env.JWT_REFRESH_SECRET = 'saved-places-test-refresh-secret-only';
process.env.REDIS_URL = '';
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');
const Passenger = require('../src/models/passenger');
const service = require('../src/services/savedPlaces.service');
let mongo;
const userId = () => new mongoose.Types.ObjectId();
const place = (name = 'Home') => ({ name, lat: 14.8, lng: 121.1 });
before(async () => {
  mongo = await MongoMemoryServer.create({ binary: { version: '8.0.28', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') } });
  await mongoose.connect(mongo.getUri());
  await Passenger.init();
});
after(async () => { await mongoose.disconnect(); if (mongo) await mongo.stop(); });

test('invalid names, coordinates and hostile payloads are rejected', () => {
  for (const body of [null, [], {}, place(' '), place('a'.repeat(61)), { ...place(), lat: null },
    { ...place(), lat: '14' }, { ...place(), lng: 181 }, { ...place(), lat: NaN },
    { ...place(), lat: Infinity }, { ...place(), name: { $ne: '' } }]) {
    assert.throws(() => service.validate(body), e => e.statusCode === 400);
  }
});
test('simultaneous duplicate saves and lost-response retries create one place', async () => {
  const owner = userId(); await Passenger.create({ userId: owner });
  await Promise.all(Array.from({ length: 15 }, () => service.add(owner, place(' Home '))));
  assert.equal((await service.list(owner)).length, 1);
  await service.add(owner, place('HOME'));
  await assert.rejects(service.add(owner, { ...place(), lat: 15 }), e => e.statusCode === 409);
});
test('concurrent saves enforce 20-place limit without lost updates', async () => {
  const owner = userId(); await Passenger.create({ userId: owner });
  const results = await Promise.allSettled(Array.from({ length: 30 }, (_, i) => service.add(owner, place(`Place ${i}`))));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 20);
  assert.equal((await service.list(owner)).length, 20);
});
test('ownership, repeated removal and missing profiles cannot modify another account', async () => {
  const owner = userId(), stranger = userId();
  await Passenger.create([{ userId: owner }, { userId: stranger }]);
  const [saved] = await service.add(owner, place());
  assert.deepEqual(await service.remove(stranger, String(saved._id)), []);
  assert.equal((await service.list(owner)).length, 1);
  await service.remove(owner, String(saved._id));
  assert.deepEqual(await service.remove(owner, String(saved._id)), []);
  await assert.rejects(service.remove(owner, 'invalid'), e => e.statusCode === 400);
  await assert.rejects(service.add(userId(), place()), e => e.statusCode === 404);
});
test('existing profiles without savedPlaces can save without a migration', async () => {
  const owner = userId();
  await Passenger.collection.insertOne({ userId: owner });
  assert.equal((await service.add(owner, place())).length, 1);
});
test('HTTP endpoints enforce authentication, role and ownership; extra identity fields are ignored', async () => {
  const express = require('express');
  const request = require('supertest');
  const User = require('../src/models/user');
  const AuthSession = require('../src/models/authSession');
  const app = express(); app.use(express.json());
  app.use('/passengers', require('../src/routes/passengers.routes'));
  app.use((error, _req, res, _next) => res.status(error.statusCode || 500).json({ message: error.message }));
  const makeToken = async (role, email) => {
    const user = await User.create({ fullName: 'Saved places test', email, role });
    const sid = require('node:crypto').randomUUID();
    await AuthSession.create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
    if (role === 'PASSENGER') await Passenger.create({ userId: user._id });
    return { user, token: require('../src/utils/jwt').signToken({ sub: String(user._id), role, sid }) };
  };
  const owner = await makeToken('PASSENGER', 'places.owner@example.test');
  const other = await makeToken('PASSENGER', 'places.other@example.test');
  const driver = await makeToken('DRIVER', 'places.driver@example.test');
  const endpoint = '/passengers/me/saved-places';
  assert.equal((await request(app).get(endpoint)).status, 401);
  assert.equal((await request(app).post(endpoint).set('Authorization', `Bearer ${driver.token}`).send(place())).status, 403);
  const saved = await request(app).post(endpoint).set('Authorization', `Bearer ${owner.token}`)
    .send({ ...place(), userId: String(other.user._id), _id: String(other.user._id) });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.data.length, 1);
  const empty = await request(app).get(endpoint).set('Authorization', `Bearer ${other.token}`);
  assert.deepEqual(empty.body.data, []);
  assert.equal(empty.headers['cache-control'], 'no-store');
  await request(app).delete(`${endpoint}/${saved.body.data[0]._id}`).set('Authorization', `Bearer ${other.token}`).expect(200);
  assert.equal((await service.list(owner.user._id)).length, 1);
  await request(app).post(endpoint).set('Authorization', `Bearer ${owner.token}`).send({ name: 'Bad', lat: null, lng: null }).expect(400);
});
