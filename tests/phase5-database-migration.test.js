const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const {
  migrationId,
  quarantineCollectionName,
  inspectPhase5Migration,
  applyPhase5Migration,
} = require('../src/migrations/phase5DatabaseMigration');

let memoryServer;

before(async () => {
  memoryServer = await MongoMemoryReplSet.create({
    binary: {
      downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries'),
      version: '8.0.28',
    },
    replSet: {
      count: 1,
      storageEngine: 'wiredTiger',
    },
  });
  const uri = memoryServer.getUri('parago-phase5-migration');
  assert.match(uri, /^mongodb:\/\/127\.0\.0\.1:/);
  await mongoose.connect(uri, { autoIndex: false });
});

after(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  await memoryServer.stop();
});

beforeEach(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.connection.db.collection('users').insertOne({
    email: 'phase5@example.test',
    fullName: 'Phase 5',
    role: 'PASSENGER',
    status: 'active',
    authProvider: 'local',
    providerId: '',
  });
});

const seedDuplicateRides = async () => {
  const pickupRequestId = new mongoose.Types.ObjectId();
  const passengerId = new mongoose.Types.ObjectId();
  const tripSessionId = new mongoose.Types.ObjectId();
  const base = new Date('2026-07-29T00:00:00.000Z');
  const result = await mongoose.connection.db.collection('ridesessions').insertMany(
    [0, 20, 40].map((offset) => ({
      passengerId,
      tripSessionId,
      pickupRequestId,
      status: 'completed',
      fareSnapshot: { amount: 14 },
      createdAt: new Date(base.getTime() + offset),
      updatedAt: new Date(base.getTime() + offset),
    }))
  );
  return {
    pickupRequestId,
    canonicalId: result.insertedIds['0'],
  };
};

test('dry-run inspection is read-only and deterministically keeps the earliest ride', async () => {
  const seeded = await seedDuplicateRides();
  const beforeCount = await mongoose.connection.db
    .collection('ridesessions')
    .countDocuments();
  const inspection = await inspectPhase5Migration(mongoose.connection.db);

  assert.equal(inspection.duplicateGroups, 1);
  assert.equal(inspection.duplicateRideSessions, 2);
  assert.equal(
    String(inspection.duplicatePlan[0].canonicalRideSessionId),
    String(seeded.canonicalId)
  );
  assert.equal(
    await mongoose.connection.db.collection('ridesessions').countDocuments(),
    beforeCount
  );
  assert.equal(
    (
      await mongoose.connection.db
        .listCollections({ name: quarantineCollectionName })
        .toArray()
    ).length,
    0
  );
});

test('apply quarantines duplicates, creates the unique index, and is idempotent', async () => {
  const seeded = await seedDuplicateRides();
  const plan = await inspectPhase5Migration(mongoose.connection.db);
  const result = await applyPhase5Migration({
    connection: mongoose.connection,
    expectedFingerprint: plan.fingerprint,
  });

  assert.equal(result.applied, true);
  assert.equal(result.after.duplicateGroups, 0);
  assert.equal(result.after.indexes.ridePickupUniquePresent, true);
  assert.equal(
    await mongoose.connection.db.collection('ridesessions').countDocuments(),
    1
  );
  assert.ok(
    await mongoose.connection.db
      .collection('ridesessions')
      .findOne({ _id: seeded.canonicalId })
  );
  assert.equal(
    await mongoose.connection.db
      .collection(quarantineCollectionName)
      .countDocuments(),
    2
  );
  assert.equal(
    await mongoose.connection.db.collection('users').countDocuments({
      providerId: { $exists: true },
    }),
    0
  );

  const rerun = await applyPhase5Migration({
    connection: mongoose.connection,
    expectedFingerprint: plan.fingerprint,
  });
  assert.equal(rerun.applied, false);
  assert.equal(rerun.idempotent, true);
  assert.equal(
    await mongoose.connection.db
      .collection(quarantineCollectionName)
      .countDocuments(),
    2
  );
  assert.equal(
    (
      await mongoose.connection.db
        .collection('schemaMigrations')
        .findOne({ migrationId })
    ).status,
    'completed'
  );
});

test('apply rejects an unapproved or stale dry-run fingerprint', async () => {
  await seedDuplicateRides();
  await assert.rejects(
    () =>
      applyPhase5Migration({
        connection: mongoose.connection,
        expectedFingerprint: 'not-the-approved-fingerprint',
      }),
    /fingerprint mismatch/i
  );
  assert.equal(
    await mongoose.connection.db.collection('ridesessions').countDocuments(),
    3
  );
});
