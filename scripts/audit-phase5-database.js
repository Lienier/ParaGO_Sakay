const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');
const dotenv = require('dotenv');
const { parseMongoTarget: parseGuardedMongoTarget } = require('./start-staging');

mongoose.set('autoIndex', false);

const rootDir = path.resolve(__dirname, '..');

const parseArgs = (argv) => {
  const environmentArg = argv.find((value) => value.startsWith('--environment='));
  const environment = environmentArg?.split('=')[1];
  if (!['production', 'staging'].includes(environment)) {
    throw new Error('Use --environment=production or --environment=staging.');
  }
  return { environment, includeForensics: argv.includes('--forensics') };
};

const loadEnvironment = (environment) => {
  const fileName = environment === 'staging' ? '.env.staging' : '.env';
  const filePath = path.join(rootDir, fileName);
  if (!fs.existsSync(filePath)) {
    throw new Error(`${fileName} is required for the Phase 5 audit.`);
  }
  return dotenv.parse(fs.readFileSync(filePath));
};

const parseMongoTarget = (uri) => {
  const parsed = parseGuardedMongoTarget(uri, 'Phase 5 MongoDB URI');
  return {
    database: parsed.database,
    host: parsed.host,
    fingerprint: crypto
      .createHash('sha256')
      .update(`${parsed.host}/${parsed.database}`)
      .digest('hex')
      .slice(0, 12),
  };
};

const assertSafeTarget = ({ environment, uri, productionUri }) => {
  if (!uri) {
    throw new Error(`Missing MongoDB URI for ${environment}.`);
  }
  const target = parseMongoTarget(uri);
  if (!target.database) {
    throw new Error('MongoDB URI must include an explicit database name.');
  }
  if (environment === 'staging') {
    if (target.database !== 'parago_staging') {
      throw new Error('Staging audit refuses any database except parago_staging.');
    }
    if (productionUri && uri === productionUri) {
      throw new Error('Staging and production MongoDB URIs must differ.');
    }
  } else if (target.database === 'parago_staging') {
    throw new Error('Production audit refuses the staging database.');
  }
  return target;
};

const summarizeExplain = (explain) => {
  const planner = explain?.queryPlanner || {};
  const execution = explain?.executionStats || {};
  return {
    winningPlanStage:
      planner.winningPlan?.queryPlan?.stage ||
      planner.winningPlan?.stage ||
      'unknown',
    totalKeysExamined: execution.totalKeysExamined ?? null,
    totalDocsExamined: execution.totalDocsExamined ?? null,
    returned: execution.nReturned ?? null,
    executionTimeMillis: execution.executionTimeMillis ?? null,
  };
};

const publicId = (value) =>
  crypto
    .createHash('sha256')
    .update(String(value || ''))
    .digest('hex')
    .slice(0, 12);

const run = async () => {
  const { environment, includeForensics } = parseArgs(process.argv.slice(2));
  const values = loadEnvironment(environment);
  const productionValues = loadEnvironment('production');
  const uri =
    environment === 'staging'
      ? values.STAGING_MONGO_URI || values.MONGO_URI
      : values.MONGO_URI;
  const target = assertSafeTarget({
    environment,
    uri,
    productionUri: productionValues.MONGO_URI,
  });

  console.log(
    JSON.stringify({
      type: 'phase5.audit.target',
      environment,
      database: target.database,
      hostFingerprint: target.fingerprint,
      mode: 'read-only',
    }),
  );

  await mongoose.connect(uri, {
    autoIndex: false,
    serverSelectionTimeoutMS: 12000,
  });

  const db = mongoose.connection.db;
  const rideSessions = db.collection('ridesessions');
  const pickupRequests = db.collection('pickuprequests');
  const tripSessions = db.collection('tripsessions');
  const jeepneys = db.collection('jeepneys');
  const quarantine = db.collection('rideSessionDuplicateQuarantine');
  const migrations = db.collection('schemaMigrations');

  const duplicateRideGroups = await rideSessions
    .aggregate([
      { $match: { pickupRequestId: { $type: 'objectId' } } },
      {
        $group: {
          _id: '$pickupRequestId',
          count: { $sum: 1 },
          rideSessionIds: { $push: '$_id' },
        },
      },
      { $match: { count: { $gt: 1 } } },
      { $sort: { count: -1 } },
      { $limit: 100 },
    ])
    .toArray();
  const quarantinedRides = await quarantine
    .find(
      { migrationId: 'phase5_database_idempotency_v1' },
      { projection: { canonicalRideSessionId: 1 } },
    )
    .toArray();
  const canonicalRideIds = [
    ...new Map(
      quarantinedRides.map((item) => [
        String(item.canonicalRideSessionId),
        item.canonicalRideSessionId,
      ]),
    ).values(),
  ];
  const retainedCanonicalRides =
    canonicalRideIds.length === 0
      ? 0
      : await rideSessions.countDocuments({ _id: { $in: canonicalRideIds } });

  const forensicGroups = [];
  if (includeForensics) {
    for (const group of duplicateRideGroups) {
      const rides = await rideSessions
        .find(
          { _id: { $in: group.rideSessionIds } },
          {
            projection: {
              passengerId: 1,
              tripSessionId: 1,
              pickupRequestId: 1,
              pickupType: 1,
              boardingMethod: 1,
              status: 1,
              boardedAt: 1,
              endedAt: 1,
              offboardingMethod: 1,
              fareSnapshot: 1,
              createdAt: 1,
              updatedAt: 1,
            },
          },
        )
        .sort({ createdAt: 1, _id: 1 })
        .toArray();
      const tripIds = [...new Set(rides.map((ride) => String(ride.tripSessionId)))];
      const trips = await tripSessions
        .find(
          {
            _id: {
              $in: tripIds
                .filter((id) => mongoose.isValidObjectId(id))
                .map((id) => new mongoose.Types.ObjectId(id)),
            },
          },
          {
            projection: {
              status: 1,
              occupancyCount: 1,
              manualOccupancyCount: 1,
              startedAt: 1,
              endedAt: 1,
            },
          },
        )
        .toArray();
      const tripById = new Map(trips.map((trip) => [String(trip._id), trip]));

      forensicGroups.push({
        pickupRequestRef: publicId(group._id),
        count: group.count,
        passengerRefs: [
          ...new Set(rides.map((ride) => publicId(ride.passengerId))),
        ],
        tripRefs: tripIds.map((tripId) => {
          const trip = tripById.get(tripId);
          return {
            ref: publicId(tripId),
            status: trip?.status || 'missing',
            occupancyCount: trip?.occupancyCount ?? null,
            manualOccupancyCount: trip?.manualOccupancyCount ?? null,
            startedAt: trip?.startedAt || null,
            endedAt: trip?.endedAt || null,
          };
        }),
        rides: rides.map((ride, index) => ({
          ordinal: index + 1,
          rideRef: publicId(ride._id),
          passengerRef: publicId(ride.passengerId),
          tripRef: publicId(ride.tripSessionId),
          pickupType: ride.pickupType || null,
          boardingMethod: ride.boardingMethod || null,
          status: ride.status,
          boardedAt: ride.boardedAt || null,
          endedAt: ride.endedAt || null,
          offboardingMethod: ride.offboardingMethod || null,
          fareAmount: ride.fareSnapshot?.amount ?? null,
          createdAt: ride.createdAt || null,
          updatedAt: ride.updatedAt || null,
        })),
      });
    }
  }

  const activePickup = await pickupRequests.findOne(
    { status: { $in: ['pending', 'acknowledged'] } },
    { projection: { passengerId: 1, tripSessionId: 1, status: 1 } },
  );
  const activeTrip = await tripSessions.findOne(
    { status: 'active' },
    { projection: { routeId: 1, jeepneyId: 1, driverId: 1 } },
  );
  const representativeRide = await rideSessions.findOne(
    { pickupRequestId: { $type: 'objectId' } },
    { projection: { pickupRequestId: 1 } },
  );

  const explains = {};
  if (representativeRide) {
    explains.rideByPickupRequest = summarizeExplain(
      await rideSessions
        .find({ pickupRequestId: representativeRide.pickupRequestId })
        .explain('executionStats'),
    );
  }
  if (activePickup) {
    explains.pickupByPassengerStatus = summarizeExplain(
      await pickupRequests
        .find({
          passengerId: activePickup.passengerId,
          status: activePickup.status,
        })
        .sort({ createdAt: -1 })
        .explain('executionStats'),
    );
    explains.rideByPassengerTripStatus = summarizeExplain(
      await rideSessions
        .find({
          passengerId: activePickup.passengerId,
          tripSessionId: activePickup.tripSessionId,
          status: { $in: ['waiting', 'onboard'] },
        })
        .explain('executionStats'),
    );
  }
  if (activeTrip) {
    explains.activeTripByJeepAndDriver = summarizeExplain(
      await tripSessions
        .find({
          jeepneyId: activeTrip.jeepneyId,
          driverId: activeTrip.driverId,
          status: 'active',
        })
        .explain('executionStats'),
    );
  }

  const report = {
    type: 'phase5.audit.result',
    environment,
    counts: {
      rideSessions: await rideSessions.countDocuments(),
      pickupRequests: await pickupRequests.countDocuments(),
      jeepneys: await jeepneys.countDocuments(),
      duplicatePickupRequestGroups: duplicateRideGroups.length,
      duplicateRideSessions: duplicateRideGroups.reduce(
        (total, group) => total + group.count,
        0,
      ),
      quarantinedPhase5Rides: quarantinedRides.length,
      expectedCanonicalRides: canonicalRideIds.length,
      retainedCanonicalRides,
      completedPhase5Migrations: await migrations.countDocuments({
        migrationId: 'phase5_database_idempotency_v1',
        status: 'completed',
      }),
    },
    duplicateGroups: duplicateRideGroups.map((group) => ({
      pickupRequestRef: publicId(group._id),
      count: group.count,
      rideSessionRefs: group.rideSessionIds.map((id) => publicId(id)),
    })),
    forensics: includeForensics ? forensicGroups : undefined,
    indexes: {
      rideSessions: await rideSessions.indexes(),
      pickupRequests: await pickupRequests.indexes(),
      tripSessions: await tripSessions.indexes(),
      jeepneys: await jeepneys.indexes(),
    },
    explains,
  };

  console.log(JSON.stringify(report, null, 2));
  if (duplicateRideGroups.length > 0) {
    process.exitCode = 2;
  }
};

run()
  .catch((error) => {
    console.error(`Phase 5 audit failed: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect();
  });
