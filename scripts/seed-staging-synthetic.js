const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

mongoose.set('autoIndex', false);

const User = require('../src/models/user');
const Admin = require('../src/models/admin');
const Driver = require('../src/models/driver');
const Passenger = require('../src/models/passenger');
const Jeepney = require('../src/models/jeepney');
const Route = require('../src/models/route');
const TripSession = require('../src/models/tripSession');
const PickupRequest = require('../src/models/pickupRequest');
const RideSession = require('../src/models/rideSession');
const SupportThread = require('../src/models/supportThread');
const SupportMessage = require('../src/models/supportMessage');
const Announcement = require('../src/models/announcement');
const Notification = require('../src/models/notification');

const rootDir = path.resolve(__dirname, '..');
const environmentPath = path.join(rootDir, '.env.staging');
const accountManifestPath = path.join(
  rootDir,
  '.secure-backups',
  'staging-synthetic-accounts.json',
);
const stagingDatabase = 'parago_staging';

function readEnvironmentValue(filePath, name) {
  const line = fs
    .readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .find((candidate) => candidate.startsWith(`${name}=`));
  return line?.slice(name.length + 1).trim() || '';
}

function assertPathInside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Credential manifest resolved outside the secure directory.');
  }
}

function point(longitude, latitude) {
  return { type: 'Point', coordinates: [longitude, latitude] };
}

function randomPassword() {
  return `${crypto.randomBytes(18).toString('base64url')}!aA9`;
}

async function main() {
  if (!fs.existsSync(environmentPath)) {
    throw new Error('.env.staging is missing.');
  }

  const stagingUri = readEnvironmentValue(
    environmentPath,
    'STAGING_MONGO_URI',
  );
  const productionUri =
    readEnvironmentValue(path.join(rootDir, '.env'), 'MONGO_URI') ||
    readEnvironmentValue(path.join(rootDir, '.env'), 'MONGODB_URI');

  if (!stagingUri.startsWith('mongodb+srv://')) {
    throw new Error('Staging URI must use mongodb+srv.');
  }
  if (!stagingUri.match(/\/parago_staging(?:\?|$)/)) {
    throw new Error('Seeder refuses a URI that does not target parago_staging.');
  }
  if (productionUri && stagingUri === productionUri) {
    throw new Error('Seeder refuses a URI matching the production database.');
  }

  assertPathInside(path.dirname(accountManifestPath), accountManifestPath);
  if (fs.existsSync(accountManifestPath)) {
    throw new Error(
      'Synthetic account manifest already exists; refusing to overwrite it.',
    );
  }

  await mongoose.connect(stagingUri, {
    autoIndex: false,
    dbName: stagingDatabase,
    serverSelectionTimeoutMS: 10000,
  });

  const existingCollections = await mongoose.connection.db
    .listCollections({}, { nameOnly: true })
    .toArray();
  if (existingCollections.length > 0) {
    throw new Error(
      `Staging is not empty (${existingCollections.length} collections); no data was written.`,
    );
  }

  const password = randomPassword();
  const passwordHash = await bcrypt.hash(password, 11);
  const now = new Date();
  const routeIds = [new mongoose.Types.ObjectId(), new mongoose.Types.ObjectId()];
  const jeepneyIds = Array.from(
    { length: 5 },
    () => new mongoose.Types.ObjectId(),
  );
  const userIds = {
    admin: new mongoose.Types.ObjectId(),
    drivers: Array.from(
      { length: 5 },
      () => new mongoose.Types.ObjectId(),
    ),
    passengers: Array.from(
      { length: 10 },
      () => new mongoose.Types.ObjectId(),
    ),
  };
  const driverIds = Array.from(
    { length: 5 },
    () => new mongoose.Types.ObjectId(),
  );
  const passengerIds = Array.from(
    { length: 10 },
    () => new mongoose.Types.ObjectId(),
  );
  const tripIds = Array.from(
    { length: 5 },
    () => new mongoose.Types.ObjectId(),
  );
  const pickupIds = Array.from(
    { length: 3 },
    () => new mongoose.Types.ObjectId(),
  );
  const rideIds = Array.from(
    { length: 2 },
    () => new mongoose.Types.ObjectId(),
  );
  const supportThreadIds = [
    new mongoose.Types.ObjectId(),
    new mongoose.Types.ObjectId(),
  ];

  const routeOnePath = [
    [120.9816, 14.5995],
    [120.9874, 14.6038],
    [120.9938, 14.6091],
    [121.0001, 14.6142],
  ];
  const routeTwoPath = [
    [121.0062, 14.6201],
    [121.0118, 14.625],
    [121.0174, 14.6302],
    [121.0232, 14.6351],
  ];

  const session = await mongoose.startSession();
  try {
    await session.withTransaction(async () => {
      await Route.insertMany(
        [
          {
            _id: routeIds[0],
            name: 'Synthetic Central Loop',
            code: 'SYN-CENTRAL',
            direction: 'up',
            status: 'active',
            description: 'Synthetic staging route. Not for public operations.',
            path: { type: 'LineString', coordinates: routeOnePath },
            stops: routeOnePath.map(([longitude, latitude], index) => ({
              name: `Synthetic Central Stop ${index + 1}`,
              code: `SYN-C-${index + 1}`,
              order: index + 1,
              fare: 15 + index * 2,
              location: point(longitude, latitude),
            })),
            navigation: {
              source: 'cached',
              distanceMeters: 4200,
              durationSeconds: 1200,
              rawDurationSeconds: 1080,
              trafficDelayInSeconds: 120,
              averageJeepSpeedKph: 18,
              trafficMultiplier: 1.1,
            },
          },
          {
            _id: routeIds[1],
            name: 'Synthetic North Loop',
            code: 'SYN-NORTH',
            direction: 'down',
            status: 'active',
            description: 'Synthetic staging route. Not for public operations.',
            path: { type: 'LineString', coordinates: routeTwoPath },
            stops: routeTwoPath.map(([longitude, latitude], index) => ({
              name: `Synthetic North Stop ${index + 1}`,
              code: `SYN-N-${index + 1}`,
              order: index + 1,
              fare: 15 + index * 2,
              location: point(longitude, latitude),
            })),
            navigation: {
              source: 'cached',
              distanceMeters: 3900,
              durationSeconds: 1080,
              rawDurationSeconds: 960,
              trafficDelayInSeconds: 120,
              averageJeepSpeedKph: 18,
              trafficMultiplier: 1.12,
            },
          },
        ],
        { session },
      );

      await User.insertMany(
        [
          {
            _id: userIds.admin,
            email: 'admin.staging@parago.example',
            passwordHash,
            fullName: 'Synthetic Staging Admin',
            role: 'ADMIN',
            status: 'active',
            isVerified: true,
          },
          ...userIds.drivers.map((userId, index) => ({
            _id: userId,
            email: `driver${index + 1}.staging@parago.example`,
            passwordHash,
            fullName: `Synthetic Driver ${index + 1}`,
            phone: `+63900000${String(index + 1).padStart(4, '0')}`,
            role: 'DRIVER',
            status: 'active',
            isVerified: true,
          })),
          ...userIds.passengers.map((userId, index) => ({
            _id: userId,
            email: `passenger${index + 1}.staging@parago.example`,
            passwordHash,
            fullName: `Synthetic Passenger ${index + 1}`,
            phone: `+63910000${String(index + 1).padStart(4, '0')}`,
            role: 'PASSENGER',
            status: 'active',
            isVerified: true,
          })),
        ],
        { session },
      );

      await Admin.create(
        [
          {
            userId: userIds.admin,
            permissions: ['synthetic_staging'],
            notes: 'Synthetic staging administrator.',
          },
        ],
        { session },
      );

      await Jeepney.insertMany(
        jeepneyIds.map((jeepneyId, index) => ({
          _id: jeepneyId,
          plateNumber: `SYN-${String(index + 1).padStart(4, '0')}`,
          capacity: 20,
          vehicleTag: `STAGING-JEEP-${index + 1}`,
          jeepneyName: `Synthetic Jeep ${index + 1}`,
          status: 'active',
          currentDriverId: driverIds[index],
          lastKnownLocation: point(
            routeOnePath[index % routeOnePath.length][0],
            routeOnePath[index % routeOnePath.length][1],
          ),
          lastSeenAt: now,
        })),
        { session },
      );

      await Driver.insertMany(
        driverIds.map((driverId, index) => ({
          _id: driverId,
          userId: userIds.drivers[index],
          licenseNumber: `SYN-LICENSE-${index + 1}`,
          employeeNumber: `SYN-DRIVER-${index + 1}`,
          phone: `+63900000${String(index + 1).padStart(4, '0')}`,
          assignedJeepneyId: jeepneyIds[index],
          assignedRouteId: routeIds[index < 3 ? 0 : 1],
          status: 'active',
        })),
        { session },
      );

      await Passenger.insertMany(
        passengerIds.map((passengerId, index) => ({
          _id: passengerId,
          userId: userIds.passengers[index],
          phone: `+63910000${String(index + 1).padStart(4, '0')}`,
          defaultRouteId: routeIds[index < 6 ? 0 : 1],
          lastKnownLocation: point(
            routeOnePath[index % routeOnePath.length][0] + 0.0001,
            routeOnePath[index % routeOnePath.length][1] + 0.0001,
          ),
          lastSeenAt: now,
        })),
        { session },
      );

      await TripSession.insertMany(
        tripIds.map((tripId, index) => {
          const routeIndex = index < 3 ? 0 : 1;
          const coordinates = routeIndex === 0 ? routeOnePath : routeTwoPath;
          return {
            _id: tripId,
            jeepneyId: jeepneyIds[index],
            driverId: driverIds[index],
            routeId: routeIds[routeIndex],
            routePathSnapshot: { type: 'LineString', coordinates },
            status: index < 4 ? 'active' : 'scheduled',
            startedAt: index < 4 ? now : undefined,
            acceptRequests: true,
            occupancyCount: index,
            active: index < 4,
            notes: 'Synthetic staging trip.',
          };
        }),
        { session },
      );

      await PickupRequest.insertMany(
        pickupIds.map((pickupId, index) => ({
          _id: pickupId,
          passengerId: passengerIds[index],
          tripSessionId: tripIds[index],
          routeId: routeIds[0],
          stopRef: `SYN-C-${index + 1}`,
          pickupLocation: point(
            routeOnePath[index][0],
            routeOnePath[index][1],
          ),
          destinationStopRef: 'SYN-C-4',
          destinationLocation: point(
            routeOnePath[3][0],
            routeOnePath[3][1],
          ),
          status: index < 2 ? 'acknowledged' : 'pending',
          acknowledgedBy: index < 2 ? driverIds[index] : undefined,
          acknowledgedAt: index < 2 ? now : undefined,
          sourceNote: 'Synthetic staging request.',
          expiresAt: new Date(now.getTime() + 24 * 60 * 60 * 1000),
        })),
        { session },
      );

      await RideSession.insertMany(
        rideIds.map((rideId, index) => ({
          _id: rideId,
          passengerId: passengerIds[index],
          tripSessionId: tripIds[index],
          pickupRequestId: pickupIds[index],
          boardingMethod: 'manual',
          boardingStopRef: `SYN-C-${index + 1}`,
          boardingLocation: point(
            routeOnePath[index][0],
            routeOnePath[index][1],
          ),
          destinationStopRef: 'SYN-C-4',
          destinationLocation: point(
            routeOnePath[3][0],
            routeOnePath[3][1],
          ),
          status: index === 0 ? 'onboard' : 'waiting',
          boardedAt: index === 0 ? now : undefined,
          canSendStopAlert: index === 0,
        })),
        { session },
      );

      await SupportThread.insertMany(
        [
          {
            _id: supportThreadIds[0],
            userId: userIds.passengers[0],
            userRole: 'PASSENGER',
            assignedAdminId: userIds.admin,
            subject: 'Synthetic passenger support thread',
            category: 'general_help',
            status: 'awaiting_admin',
            routeId: routeIds[0],
            lastMessageAt: now,
            lastMessagePreview: 'Synthetic passenger support message.',
            lastMessageSenderRole: 'PASSENGER',
            unreadAdminCount: 1,
          },
          {
            _id: supportThreadIds[1],
            userId: userIds.drivers[0],
            userRole: 'DRIVER',
            assignedAdminId: userIds.admin,
            subject: 'Synthetic driver support thread',
            category: 'trip_issue',
            status: 'awaiting_user',
            tripSessionId: tripIds[0],
            routeId: routeIds[0],
            lastMessageAt: now,
            lastMessagePreview: 'Synthetic admin response.',
            lastMessageSenderRole: 'ADMIN',
            unreadUserCount: 1,
          },
        ],
        { session },
      );

      await SupportMessage.insertMany(
        [
          {
            threadId: supportThreadIds[0],
            senderId: userIds.passengers[0],
            senderRole: 'PASSENGER',
            body: 'Synthetic passenger support message.',
          },
          {
            threadId: supportThreadIds[1],
            senderId: userIds.drivers[0],
            senderRole: 'DRIVER',
            body: 'Synthetic driver support message.',
          },
          {
            threadId: supportThreadIds[1],
            senderId: userIds.admin,
            senderRole: 'ADMIN',
            body: 'Synthetic admin response.',
          },
        ],
        { session },
      );

      await Announcement.create(
        [
          {
            title: 'Synthetic staging service notice',
            body: 'This announcement is synthetic and exists only for staging validation.',
            category: 'service_change',
            severity: 'info',
            audiences: ['PASSENGER', 'DRIVER'],
            status: 'published',
            startsAt: now,
            publishedAt: now,
            createdByAdminId: userIds.admin,
            updatedByAdminId: userIds.admin,
          },
        ],
        { session },
      );

      await Notification.insertMany(
        [
          {
            userId: userIds.passengers[0],
            type: 'synthetic_staging',
            title: 'Synthetic passenger notification',
            body: 'Staging-only notification.',
          },
          {
            userId: userIds.drivers[0],
            type: 'synthetic_staging',
            title: 'Synthetic driver notification',
            body: 'Staging-only notification.',
          },
        ],
        { session },
      );
    });
  } finally {
    await session.endSession();
  }

  const accounts = {
    generatedAt: now.toISOString(),
    environment: 'staging',
    database: stagingDatabase,
    warning: 'Synthetic staging accounts only. Never use these credentials in production.',
    sharedPassword: password,
    accounts: {
      admin: ['admin.staging@parago.example'],
      drivers: userIds.drivers.map(
        (_, index) => `driver${index + 1}.staging@parago.example`,
      ),
      passengers: userIds.passengers.map(
        (_, index) => `passenger${index + 1}.staging@parago.example`,
      ),
    },
  };
  fs.writeFileSync(
    accountManifestPath,
    `${JSON.stringify(accounts, null, 2)}\n`,
    { encoding: 'utf8', mode: 0o600, flag: 'wx' },
  );

  const collections = await mongoose.connection.db
    .listCollections({}, { nameOnly: true })
    .toArray();
  let documentCount = 0;
  for (const collection of collections) {
    documentCount += await mongoose.connection.db
      .collection(collection.name)
      .countDocuments();
  }

  console.log(`Synthetic staging seed complete: ${collections.length} collections.`);
  console.log(`Synthetic staging seed complete: ${documentCount} documents.`);
  console.log(`Credentials saved locally at ${accountManifestPath}.`);
  console.log('No production records were copied to staging.');
}

main()
  .catch((error) => {
    console.error(`Synthetic staging seed failed: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
