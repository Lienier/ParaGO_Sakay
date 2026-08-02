const crypto = require('crypto');

const migrationId = 'phase5_database_idempotency_v1';
const ridePickupIndexName = 'uniq_ride_session_pickup_request';
const quarantineCollectionName = 'rideSessionDuplicateQuarantine';
const migrationCollectionName = 'schemaMigrations';

const objectIdString = (value) => String(value || '');

const findDuplicateRideGroups = async (db) =>
  db
    .collection('ridesessions')
    .aggregate([
      { $match: { pickupRequestId: { $type: 'objectId' } } },
      {
        $group: {
          _id: '$pickupRequestId',
          count: { $sum: 1 },
          rides: {
            $push: {
              id: '$_id',
              createdAt: '$createdAt',
            },
          },
        },
      },
      { $match: { count: { $gt: 1 } } },
      { $sort: { _id: 1 } },
    ])
    .toArray();

const sortRideCandidates = (rides) =>
  [...rides].sort((left, right) => {
    const leftCreated = new Date(left.createdAt || 0).getTime();
    const rightCreated = new Date(right.createdAt || 0).getTime();
    if (leftCreated !== rightCreated) return leftCreated - rightCreated;
    return objectIdString(left.id).localeCompare(objectIdString(right.id));
  });

const buildDuplicatePlan = (groups) =>
  groups.map((group) => {
    const rides = sortRideCandidates(group.rides);
    return {
      pickupRequestId: group._id,
      canonicalRideSessionId: rides[0].id,
      duplicateRideSessionIds: rides.slice(1).map((ride) => ride.id),
    };
  });

const fingerprintPlan = (plan) => {
  const serialized = plan
    .map((group) => ({
      pickupRequestId: objectIdString(group.pickupRequestId),
      canonicalRideSessionId: objectIdString(group.canonicalRideSessionId),
      duplicateRideSessionIds: group.duplicateRideSessionIds
        .map(objectIdString)
        .sort(),
    }))
    .sort((left, right) =>
      left.pickupRequestId.localeCompare(right.pickupRequestId)
    );
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(serialized))
    .digest('hex');
};

const inspectPhase5Migration = async (db) => {
  const groups = await findDuplicateRideGroups(db);
  const duplicatePlan = buildDuplicatePlan(groups);
  const rideIndexes = await db.collection('ridesessions').indexes();
  const userIndexes = await db.collection('users').indexes();
  const blankProviderIds = await db.collection('users').countDocuments({
    providerId: { $exists: true, $in: [null, ''] },
  });
  const migrationRecord = await db
    .collection(migrationCollectionName)
    .findOne({ migrationId });

  return {
    migrationId,
    fingerprint: fingerprintPlan(duplicatePlan),
    duplicateGroups: duplicatePlan.length,
    duplicateRideSessions: duplicatePlan.reduce(
      (total, group) => total + group.duplicateRideSessionIds.length,
      0
    ),
    duplicatePlan,
    blankProviderIds,
    indexes: {
      ridePickupUniquePresent: rideIndexes.some(
        (index) =>
          index.name === ridePickupIndexName &&
          index.unique === true &&
          index.key?.pickupRequestId === 1
      ),
      userEmailUniquePresent: userIndexes.some(
        (index) =>
          index.name === 'email_1' &&
          index.unique === true &&
          index.key?.email === 1
      ),
      userProviderUniquePresent: userIndexes.some(
        (index) =>
          index.unique === true &&
          index.key?.authProvider === 1 &&
          index.key?.providerId === 1
      ),
    },
    migrationStatus: migrationRecord?.status || null,
    migrationFingerprint: migrationRecord?.fingerprint || null,
    alreadyCompleted: migrationRecord?.status === 'completed',
  };
};

const reconcileDuplicateRides = async ({
  db,
  session,
  duplicatePlan,
  appliedAt,
}) => {
  const rides = db.collection('ridesessions');
  const quarantine = db.collection(quarantineCollectionName);

  for (const group of duplicatePlan) {
    const duplicateDocuments = await rides
      .find(
        { _id: { $in: group.duplicateRideSessionIds } },
        { session }
      )
      .toArray();
    if (duplicateDocuments.length !== group.duplicateRideSessionIds.length) {
      throw new Error('Duplicate ride set changed before quarantine.');
    }

    if (duplicateDocuments.length > 0) {
      await quarantine.insertMany(
        duplicateDocuments.map((document) => ({
          migrationId,
          originalRideSessionId: document._id,
          canonicalRideSessionId: group.canonicalRideSessionId,
          pickupRequestId: group.pickupRequestId,
          reason: 'concurrent_boarding_duplicate',
          quarantinedAt: appliedAt,
          originalDocument: document,
        })),
        { session }
      );
      const deletion = await rides.deleteMany(
        { _id: { $in: group.duplicateRideSessionIds } },
        { session }
      );
      if (deletion.deletedCount !== duplicateDocuments.length) {
        throw new Error('Duplicate ride deletion count did not match quarantine.');
      }
    }
  }
};

const ensurePhase5Indexes = async (db) => {
  await db.collection(quarantineCollectionName).createIndex(
    { originalRideSessionId: 1 },
    { unique: true, name: 'uniq_quarantined_ride_session' }
  );
  await db.collection(migrationCollectionName).createIndex(
    { migrationId: 1 },
    { unique: true, name: 'uniq_schema_migration_id' }
  );
  await db.collection('ridesessions').createIndex(
    { pickupRequestId: 1 },
    {
      unique: true,
      name: ridePickupIndexName,
      partialFilterExpression: {
        pickupRequestId: { $type: 'objectId' },
      },
    }
  );
  await db.collection('users').createIndex(
    { email: 1 },
    { unique: true, name: 'email_1' }
  );
  await db.collection('users').createIndex(
    { role: 1, status: 1 },
    { name: 'role_1_status_1' }
  );
  await db.collection('users').createIndex(
    { authProvider: 1, providerId: 1 },
    {
      unique: true,
      name: 'authProvider_1_providerId_1',
      partialFilterExpression: {
        providerId: { $exists: true, $type: 'string' },
      },
    }
  );
};

const applyPhase5Migration = async ({
  connection,
  expectedFingerprint,
}) => {
  const db = connection.db;
  const before = await inspectPhase5Migration(db);
  if (before.alreadyCompleted) {
    return { applied: false, idempotent: true, before, after: before };
  }
  if (before.migrationStatus === 'data_reconciled') {
    if (before.migrationFingerprint !== expectedFingerprint) {
      throw new Error('Interrupted migration fingerprint does not match.');
    }
    await ensurePhase5Indexes(db);
    await db.collection(migrationCollectionName).updateOne(
      { migrationId, status: 'data_reconciled' },
      { $set: { status: 'completed', completedAt: new Date() } }
    );
    const after = await inspectPhase5Migration(db);
    return { applied: true, idempotent: true, before, after };
  }
  if (!expectedFingerprint || expectedFingerprint !== before.fingerprint) {
    throw new Error(
      'Migration fingerprint mismatch; run and approve a fresh dry-run.'
    );
  }

  const appliedAt = new Date();
  const session = await connection.startSession();
  try {
    await session.withTransaction(async () => {
      const duplicateGroups = await findDuplicateRideGroups(db);
      const currentPlan = buildDuplicatePlan(duplicateGroups);
      if (fingerprintPlan(currentPlan) !== expectedFingerprint) {
        throw new Error('Duplicate ride set changed during migration.');
      }

      await reconcileDuplicateRides({
        db,
        session,
        duplicatePlan: currentPlan,
        appliedAt,
      });
      await db.collection('users').updateMany(
        { providerId: { $exists: true, $in: [null, ''] } },
        { $unset: { providerId: '' } },
        { session }
      );
      await db.collection(migrationCollectionName).insertOne(
        {
          migrationId,
          status: 'data_reconciled',
          fingerprint: expectedFingerprint,
          appliedAt,
        },
        { session }
      );
    });
  } finally {
    await session.endSession();
  }

  await ensurePhase5Indexes(db);
  await db.collection(migrationCollectionName).updateOne(
    { migrationId },
    {
      $set: {
        status: 'completed',
        completedAt: new Date(),
      },
    }
  );

  const after = await inspectPhase5Migration(db);
  if (
    after.duplicateGroups !== 0 ||
    !after.indexes.ridePickupUniquePresent ||
    !after.alreadyCompleted
  ) {
    throw new Error('Phase 5 post-migration verification failed.');
  }
  return { applied: true, idempotent: false, before, after };
};

module.exports = {
  migrationId,
  ridePickupIndexName,
  quarantineCollectionName,
  migrationCollectionName,
  findDuplicateRideGroups,
  buildDuplicatePlan,
  fingerprintPlan,
  inspectPhase5Migration,
  applyPhase5Migration,
};
