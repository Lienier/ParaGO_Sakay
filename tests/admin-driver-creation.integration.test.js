const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const express = require('express');
const request = require('supertest');
const sharp = require('sharp');
process.env.DRIVER_DOCUMENTS_BUCKET = 'isolated-driver-test';
const User = require('../src/models/user');
const Driver = require('../src/models/driver');
const Jeepney = require('../src/models/jeepney');
const AuthSession = require('../src/models/authSession');
const { signToken } = require('../src/utils/jwt');
const { setS3ClientForTests } = require('../src/services/driverLicenseDocuments.service');
const app = express();
app.use(express.json());
app.use('/admin', require('../src/routes/admin.routes'));
app.use((error, req, res, next) => res.status(error.statusCode || 500).json({ message: error.message }));
let repl, token, picture;
const commands = [];
let failStorage = false;
let failOnPut = 0, putCount = 0;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries'), version: '8.0.28' }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri());
  await Promise.all(Object.values(mongoose.models).map(m => m.init()));
  const user = await User.create({ email: 'creator@example.test', fullName: 'Admin', role: 'ADMIN' });
  const sid = crypto.randomUUID();
  await AuthSession.create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  token = signToken({ sub: String(user._id), sid, role: user.role });
  picture = await sharp({ create: { width: 10, height: 10, channels: 3, background: '#ffffff' } }).png().toBuffer();
  setS3ClientForTests({ send: async command => {
    commands.push(command);
    if (command.constructor.name === 'PutObjectCommand') {
      putCount++;
      if (failStorage || putCount === failOnPut) throw new Error('Simulated storage unavailable');
    }
    return {};
  } });
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });
const create = (
  email,
  plate = 'TEST1234',
  { phone = '09000000000', licenseNumber = 'TEST-LICENSE' } = {}
) => request(app).post('/admin/drivers')
  .set('Authorization', `Bearer ${token}`)
  .field('payload', JSON.stringify({ email, password: 'Local-Only-Test-2026!', fullName: 'Test Driver', phone, licenseNumber, jeepney: { plateNumber: plate, capacity: 20 } }))
  .attach('licenseFront', picture, { filename: 'front.png', contentType: 'image/png' })
  .attach('licenseBack', picture, { filename: 'back.png', contentType: 'image/png' });

test('fully populated form creates driver and jeep without a GPS location', async () => {
  const result = await create('created@example.test');
  assert.equal(result.status, 201, result.text);
  const user = await User.findOne({ email: 'created@example.test' });
  const driver = await Driver.findOne({ userId: user._id }).select('+licenseDocuments');
  assert.ok(driver.licenseDocuments.front.objectKey);
  assert.ok(driver.assignedJeepneyId);
  assert.equal(await Jeepney.countDocuments({ currentDriverId: driver._id }), 1);
});

test('duplicate and storage failure do not leave partial accounts', async () => {
  await create('created@example.test', 'OTHER5678').expect(409);
  failStorage = true;
  const failed = await create('failed@example.test', 'FAIL5678', {
    licenseNumber: 'FAIL-LICENSE',
  });
  failStorage = false;
  assert.ok(failed.status >= 500);
  assert.equal(await User.countDocuments({ email: 'failed@example.test' }), 0);
  assert.equal(await Jeepney.countDocuments({ plateNumber: 'FAIL5678' }), 0);
});


test('second image failure cleans the first upload without creating any account', async () => {
  commands.length = 0; putCount = 0; failOnPut = 2;
  const result = await create('back-failed@example.test', 'BACK1234', {
    licenseNumber: 'BACK-LICENSE',
  });
  assert.equal(result.status, 503);
  assert.match(result.body.message, /storage is unavailable/);
  assert.equal(await User.countDocuments({ email: 'back-failed@example.test' }), 0);
  assert.equal(commands.filter(c => c.constructor.name === 'DeleteObjectCommand').length, 1);
  failOnPut = 0;
});

test('corrupt image is a validation failure, not an unexplained server error', async () => {
  const saved = picture;
  picture = Buffer.from('not an actual PNG');
  const result = await create('corrupt@example.test', 'BAD1234', {
    licenseNumber: 'CORRUPT-LICENSE',
  });
  picture = saved;
  assert.equal(result.status, 400);
  assert.match(result.body.message, /image could not be read/);
  assert.equal(await User.countDocuments({ email: 'corrupt@example.test' }), 0);
});


test('concurrent creation and lost-response retry cannot duplicate driver or vehicle', async () => {
  const results = await Promise.all([
    create('race@example.test', 'RACE1234', { licenseNumber: 'RACE-LICENSE' }),
    create('race@example.test', 'RACE1234', { licenseNumber: 'RACE-LICENSE' }),
  ]);
  assert.deepEqual(results.map(r => r.status).sort(), [201, 409]);
  await create('race@example.test', 'RACE1234', { licenseNumber: 'RACE-LICENSE' }).expect(409);
  assert.equal(await User.countDocuments({ email: 'race@example.test' }), 1);
  assert.equal(await Jeepney.countDocuments({ plateNumber: 'RACE1234' }), 1);
});

test('driver CP number follows the exact 09 plus nine digits rule', async () => {
  for (const [index, phone] of [
    ['short', '0900000000'],
    ['prefix', '08000000000'],
    ['letters', '09ABC000000'],
    ['spaces', '09 000000000'],
    ['symbols', '09-000000000'],
  ]) {
    const result = await create(
      `invalid-cp-${index}@example.test`,
      `CP${index}1234`,
      { phone, licenseNumber: `CP-${index}` }
    );
    assert.equal(result.status, 400, `${index}: ${result.text}`);
    assert.match(result.body.message, /CP number/i);
  }
  const valid = await create(
    'valid-cp@example.test',
    'CPVALID1234',
    { phone: '09123456789', licenseNumber: 'CP VALID' }
  );
  assert.equal(valid.status, 201, valid.text);
});

test('license numbers are normalized and unique across driver accounts', async () => {
  const duplicate = await create(
    'duplicate-license@example.test',
    'LICDUP1234',
    { licenseNumber: ' test-license ' }
  );
  assert.equal(duplicate.status, 409, duplicate.text);
  assert.match(duplicate.body.message, /license number/i);

  const first = await create(
    'normalized-license@example.test',
    'LICNORM1234',
    { licenseNumber: 'Unique  License' }
  );
  assert.equal(first.status, 201, first.text);
  const second = await create(
    'normalized-license-2@example.test',
    'LICNORM2234',
    { licenseNumber: ' unique license ' }
  );
  assert.equal(second.status, 409, second.text);
  assert.match(second.body.message, /license number/i);
});
