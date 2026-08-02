const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');

const {
  loadManifestPath,
  loadStagingBoundary,
  positiveInteger,
  writeSecureJson,
} = require('./phase10-safety');

mongoose.set('autoIndex', false);

const User = require('../src/models/user');
const Driver = require('../src/models/driver');
const Passenger = require('../src/models/passenger');
const Jeepney = require('../src/models/jeepney');
const Route = require('../src/models/route');
const TripSession = require('../src/models/tripSession');

const routeCode = 'P10-LOAD';
const defaultDriverCount = 100;
const defaultPassengerCount = 500;
const maximumDriverCount = 200;
const maximumPassengerCount = 1000;
const routeCoordinates = [
  [120.9816, 14.5995],
  [120.9874, 14.6038],
  [120.9938, 14.6091],
  [121.0001, 14.6142],
  [121.0062, 14.6201],
];

const objectId = () => new mongoose.Types.ObjectId();
const point = ([longitude, latitude]) => ({
  type: 'Point',
  coordinates: [longitude, latitude],
});

const buildPlan = ({ driverCount, passengerCount, now }) => {
  const routeId = objectId();
  const drivers = Array.from({ length: driverCount }, (_, index) => ({
    number: index + 1,
    userId: objectId(),
    driverId: objectId(),
    jeepneyId: objectId(),
    tripId: objectId(),
    email: `phase10.driver.${String(index + 1).padStart(3, '0')}@parago.example`,
    coordinate: routeCoordinates[index % routeCoordinates.length],
  }));
  const passengers = Array.from({ length: passengerCount }, (_, index) => ({
    number: index + 1,
    userId: objectId(),
    passengerId: objectId(),
    email: `phase10.passenger.${String(index + 1).padStart(4, '0')}@parago.example`,
    coordinate: routeCoordinates[index % routeCoordinates.length],
  }));
  return { routeId, drivers, passengers, now };
};

const resolveExistingIds = async (plan) => {
  const route = await Route.findOne({ code: routeCode }).select('_id');
  if (route) plan.routeId = route._id;

  const emails = [
    ...plan.drivers.map((entry) => entry.email),
    ...plan.passengers.map((entry) => entry.email),
  ];
  const users = await User.find({ email: { $in: emails } }).select('_id email');
  const userByEmail = new Map(users.map((user) => [user.email, user._id]));
  for (const entry of [...plan.drivers, ...plan.passengers]) {
    entry.userId = userByEmail.get(entry.email) || entry.userId;
  }

  const driverProfiles = await Driver.find({
    userId: { $in: plan.drivers.map((entry) => entry.userId) },
  }).select('_id userId assignedJeepneyId');
  const driverByUser = new Map(
    driverProfiles.map((driver) => [String(driver.userId), driver])
  );
  for (const entry of plan.drivers) {
    const existing = driverByUser.get(String(entry.userId));
    if (existing) {
      entry.driverId = existing._id;
      entry.jeepneyId = existing.assignedJeepneyId || entry.jeepneyId;
    }
  }

  const jeeps = await Jeepney.find({
    plateNumber: { $in: plan.drivers.map((entry) => `P10-${String(entry.number).padStart(4, '0')}`) },
  }).select('_id plateNumber');
  const jeepByPlate = new Map(jeeps.map((jeep) => [jeep.plateNumber, jeep._id]));
  for (const entry of plan.drivers) {
    entry.jeepneyId =
      jeepByPlate.get(`P10-${String(entry.number).padStart(4, '0')}`) ||
      entry.jeepneyId;
  }

  const trips = await TripSession.find({
    jeepneyId: { $in: plan.drivers.map((entry) => entry.jeepneyId) },
    status: 'active',
  }).select('_id jeepneyId');
  const tripByJeep = new Map(
    trips.map((trip) => [String(trip.jeepneyId), trip._id])
  );
  for (const entry of plan.drivers) {
    entry.tripId = tripByJeep.get(String(entry.jeepneyId)) || entry.tripId;
  }

  const passengerProfiles = await Passenger.find({
    userId: { $in: plan.passengers.map((entry) => entry.userId) },
  }).select('_id userId');
  const passengerByUser = new Map(
    passengerProfiles.map((passenger) => [String(passenger.userId), passenger._id])
  );
  for (const entry of plan.passengers) {
    entry.passengerId =
      passengerByUser.get(String(entry.userId)) || entry.passengerId;
  }
};

const bulkUpsert = (Model, operations) =>
  Model.bulkWrite(operations, { ordered: false });

async function main() {
  const driverCount = positiveInteger(
    process.env.PHASE10_DRIVER_FIXTURES || defaultDriverCount,
    'PHASE10_DRIVER_FIXTURES',
    maximumDriverCount
  );
  const passengerCount = positiveInteger(
    process.env.PHASE10_PASSENGER_FIXTURES || defaultPassengerCount,
    'PHASE10_PASSENGER_FIXTURES',
    maximumPassengerCount
  );
  const { staging, stagingUri, targets } = loadStagingBoundary();
  const jwtSecret = staging.STAGING_JWT_SECRET;
  if (!jwtSecret || jwtSecret.length < 32) {
    throw new Error('STAGING_JWT_SECRET must contain at least 32 characters');
  }

  await mongoose.connect(stagingUri, {
    autoIndex: false,
    dbName: 'parago_staging',
    serverSelectionTimeoutMS: 10000,
  });

  const now = new Date();
  const plan = buildPlan({ driverCount, passengerCount, now });
  await resolveExistingIds(plan);
  const sharedPassword = `${crypto.randomBytes(18).toString('base64url')}!aA9`;
  const passwordHash = await bcrypt.hash(sharedPassword, 11);

  await Route.updateOne(
    { code: routeCode },
    {
      $set: {
        name: 'Phase 10 Synthetic Capacity Route',
        direction: 'up',
        status: 'active',
        description: 'Synthetic load-test route. Never use for public operations.',
        path: { type: 'LineString', coordinates: routeCoordinates },
        stops: routeCoordinates.map((coordinate, index) => ({
          name: `Phase 10 Stop ${index + 1}`,
          code: `P10-${index + 1}`,
          order: index + 1,
          fare: 15 + index * 2,
          location: point(coordinate),
        })),
        navigation: {
          source: 'cached',
          distanceMeters: 6500,
          durationSeconds: 1800,
          rawDurationSeconds: 1500,
          trafficDelayInSeconds: 300,
          averageJeepSpeedKph: 18,
          trafficMultiplier: 1.2,
        },
      },
      $setOnInsert: { _id: plan.routeId },
    },
    { upsert: true }
  );
  const route = await Route.findOne({ code: routeCode }).select('_id');
  plan.routeId = route._id;

  await bulkUpsert(User, [
    ...plan.drivers.map((entry) => ({
      updateOne: {
        filter: { email: entry.email },
        update: {
          $set: {
            passwordHash,
            fullName: `Phase 10 Driver ${entry.number}`,
            role: 'DRIVER',
            authProvider: 'local',
            status: 'active',
            isVerified: true,
          },
          $setOnInsert: { _id: entry.userId },
        },
        upsert: true,
      },
    })),
    ...plan.passengers.map((entry) => ({
      updateOne: {
        filter: { email: entry.email },
        update: {
          $set: {
            passwordHash,
            fullName: `Phase 10 Passenger ${entry.number}`,
            role: 'PASSENGER',
            authProvider: 'local',
            status: 'active',
            isVerified: true,
          },
          $setOnInsert: { _id: entry.userId },
        },
        upsert: true,
      },
    })),
  ]);
  await resolveExistingIds(plan);

  await bulkUpsert(Jeepney, plan.drivers.map((entry) => ({
    updateOne: {
      filter: { plateNumber: `P10-${String(entry.number).padStart(4, '0')}` },
      update: {
        $set: {
          capacity: 20,
          vehicleTag: `PHASE10-JEEP-${entry.number}`,
          jeepneyName: `Phase 10 Jeep ${entry.number}`,
          status: 'active',
          currentDriverId: entry.driverId,
          lastKnownLocation: point(entry.coordinate),
          lastSeenAt: now,
        },
        $setOnInsert: { _id: entry.jeepneyId },
      },
      upsert: true,
    },
  })));
  await resolveExistingIds(plan);

  await bulkUpsert(Driver, plan.drivers.map((entry) => ({
    updateOne: {
      filter: { userId: entry.userId },
      update: {
        $set: {
          licenseNumber: `PHASE10-LICENSE-${entry.number}`,
          employeeNumber: `PHASE10-DRIVER-${entry.number}`,
          assignedJeepneyId: entry.jeepneyId,
          assignedRouteId: plan.routeId,
          status: 'active',
          operatingMode: 'route',
          terminalQueueStatus: 'off_queue',
        },
        $setOnInsert: { _id: entry.driverId },
      },
      upsert: true,
    },
  })));
  await resolveExistingIds(plan);

  await bulkUpsert(TripSession, plan.drivers.map((entry) => ({
    updateOne: {
      filter: { _id: entry.tripId },
      update: {
        $set: {
          jeepneyId: entry.jeepneyId,
          driverId: entry.driverId,
          routeId: plan.routeId,
          routePathSnapshot: {
            type: 'LineString',
            coordinates: routeCoordinates,
          },
          status: 'active',
          startedAt: now,
          acceptRequests: true,
          active: true,
          operatingMode: 'route',
          terminalQueueStatus: 'off_queue',
          notes: 'Phase 10 synthetic capacity trip.',
        },
        $setOnInsert: { _id: entry.tripId },
      },
      upsert: true,
    },
  })));

  await bulkUpsert(Passenger, plan.passengers.map((entry) => ({
    updateOne: {
      filter: { userId: entry.userId },
      update: {
        $set: {
          defaultRouteId: plan.routeId,
          lastKnownLocation: point(entry.coordinate),
          lastSeenAt: now,
        },
        $setOnInsert: { _id: entry.passengerId },
      },
      upsert: true,
    },
  })));

  const tokenFor = (entry, role) =>
    jwt.sign({ sub: String(entry.userId), role }, jwtSecret, { expiresIn: '12h' });
  writeSecureJson(loadManifestPath, {
    schemaVersion: 1,
    generatedAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + 12 * 60 * 60 * 1000).toISOString(),
    environment: 'staging',
    database: targets.staging.database,
    atlasHostFingerprint: crypto
      .createHash('sha256')
      .update(targets.staging.host)
      .digest('hex')
      .slice(0, 12),
    routeId: String(plan.routeId),
    routeCoordinates,
    sharedPassword,
    drivers: plan.drivers.map((entry) => ({
      email: entry.email,
      token: tokenFor(entry, 'DRIVER'),
      jeepneyId: String(entry.jeepneyId),
      tripId: String(entry.tripId),
    })),
    passengers: plan.passengers.map((entry) => ({
      email: entry.email,
      token: tokenFor(entry, 'PASSENGER'),
    })),
  });

  console.log(
    `Phase 10 fixtures ready: ${driverCount} drivers, ${passengerCount} passengers.`
  );
  console.log(`Target database: ${targets.staging.database}.`);
  console.log(`Credentials and tokens saved to ${loadManifestPath}.`);
  console.log('No production records or services were read or modified.');
}

if (require.main === module) {
  main()
    .catch((error) => {
      console.error(`Phase 10 fixture preparation failed: ${error.message}`);
      process.exitCode = 1;
    })
    .finally(async () => {
      await mongoose.disconnect().catch(() => {});
    });
}

module.exports = {
  buildPlan,
  defaultDriverCount,
  defaultPassengerCount,
  maximumDriverCount,
  maximumPassengerCount,
  routeCode,
};
