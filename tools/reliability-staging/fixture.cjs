// Loopback-only system lab. Never loads .env, Atlas, or cloud credentials.
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
require('dotenv').config = () => ({ parsed: {} });
Object.assign(process.env, {
  NODE_ENV: 'test', DEPLOYMENT_ENV: 'test', MONGO_URI: 'mongodb://127.0.0.1/unused',
  JWT_SECRET: crypto.randomBytes(48).toString('hex'),
  JWT_REFRESH_SECRET: crypto.randomBytes(48).toString('hex'),
  REDIS_URL: 'redis://127.0.0.1:6398', REDIS_NAMESPACE: `parago:test:playwright:${crypto.randomBytes(6).toString('hex')}`,
  GROUP_BOOKINGS_ENABLED: 'true', AUTOMATIC_GROUP_FLOW_ENABLED: 'false', AUTOMATIC_DRIVER_LIFECYCLE_ENABLED: 'false', RUN_API_JOBS: 'false',
  FIREBASE_PROJECT_ID: '', FIREBASE_CLIENT_EMAIL: '', FIREBASE_PRIVATE_KEY: '',
  GOOGLE_APPLICATION_CREDENTIALS: '', GOOGLE_CLIENT_IDS: '', FACEBOOK_APP_TOKEN: '',
  TOMTOM_API_KEY: '', GOOGLE_ROUTES_API_KEY: '', SMSAPIPH_API_KEY: '',
  AUTH_EMAIL_ENABLED: 'false', DRIVER_DOCUMENTS_BUCKET: '',
  ASYNC_LOCATION_PROCESSING_ENABLED: 'false', ASYNC_NOTIFICATION_DELIVERY_ENABLED: 'false',
  CORS_ALLOWED_ORIGINS: 'http://127.0.0.1:8768',
});
const mailbox = [];
// Only outbound email transport is replaced; OTP creation, hashing, expiry,
// validation, session creation, and API handlers are the real application code.
const emailModule = require.resolve('../../src/services/authEmail.service');
require.cache[emailModule] = { id: emailModule, filename: emailModule, loaded: true, exports: {
  ensureAuthEmailAvailable: async () => {},
  sendAuthEmail: async message => { mailbox.push(message); },
} };
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const express = require('express');
const http = require('node:http');
const apiOrigin = 'http://127.0.0.1:5068';
const webOrigin = 'http://127.0.0.1:8768';
const password = 'Local-Playwright-Only-2026!';
const point = (lat = 14.9) => ({ type: 'Point', coordinates: [121.05, lat] });

async function createLab() {
  let repl, apiServer, webServer;
  const sockets = require('../../src/realtime/socketServer');
  const redis = require('../../src/services/redis.service');
  const closeServer = s => s && new Promise(resolve => s.close(resolve));
  const stop = async () => {
    await sockets.closeSocketServer();
    await Promise.all([closeServer(apiServer), closeServer(webServer)]);
    await mongoose.disconnect();
    await redis.shutdownRedis();
    if (repl) await repl.stop();
  };
  try {
    if (!await redis.initializeRedis()) throw Error('Start dedicated loopback Redis on port 6398 before running this lab');
    console.log('Starting isolated MongoDB replica set');
    const cacheDir = path.join(os.tmpdir(), 'parago-mongodb-binaries');
    const cachedBinary = path.join(cacheDir, 'mongod-x64-win32-8.2.6.exe');
    repl = await MongoMemoryReplSet.create({ binary: {
      version: '8.2.6', downloadDir: cacheDir,
      ...(require('node:fs').existsSync(cachedBinary) ? { systemBinary: cachedBinary } : {}),
    }, replSet: { count: 1, ip: '127.0.0.1' } });
    const uri = repl.getUri('playwright_system_test');
    if (!/^mongodb:\/\/127\.0\.0\.1:/.test(uri)) throw Error('Local database isolation check failed');
    await mongoose.connect(uri);
    console.log('Isolated MongoDB connected; creating synthetic accounts');
    const User = require('../../src/models/user');
    const Passenger = require('../../src/models/passenger');
    const Driver = require('../../src/models/driver');
    const Admin = require('../../src/models/admin');
    const Route = require('../../src/models/route');
    const Jeepney = require('../../src/models/jeepney');
    const Trip = require('../../src/models/tripSession');
    const AuthSession = require('../../src/models/authSession');
    const hash = await require('bcryptjs').hash(password, 10);
    async function account(label, role) {
      return User.create({ email: `${label}.playwright@example.test`, fullName: `Playwright ${label}`, role, status: 'active', passwordHash: hash,
        legalAcceptance: { termsVersion: '2026-10-03', privacyVersion: '2026-10-03', acceptedAt: new Date() } });
    }
    const admin = await account('admin', 'ADMIN');
    await Admin.create({ userId: admin._id });
    const driverUser = await account('driver', 'DRIVER');
    const otherDriverUser = await account('other-driver', 'DRIVER');
    const passengerUser = await account('passenger', 'PASSENGER');
    const otherPassengerUser = await account('other-passenger', 'PASSENGER');
    const passenger = await Passenger.create({ userId: passengerUser._id });
    await Passenger.create({ userId: otherPassengerUser._id });
    const route = await Route.create({ name: 'Playwright Main Route', code: 'PW-MAIN', direction: 'up', status: 'active',
      path: { type: 'LineString', coordinates: [[121.05, 14.9], [121.05, 14.93]] },
      terminal: { enabled: true, name: 'Playwright Terminal', stopRef: 'PW-START', location: point(), radiusMeters: 100 },
      stops: [{ name: 'Playwright Terminal', code: 'PW-START', order: 0, fare: 0, location: point() },
        { name: 'Playwright Destination', code: 'PW-END', order: 1, fare: 20, location: point(14.93) }] });
    const jeepney = await Jeepney.create({ plateNumber: 'PW 123', capacity: 6, status: 'active', lastKnownLocation: point(), lastSeenAt: new Date() });
    const driver = await Driver.create({ userId: driverUser._id, licenseNumber: 'N01-23-456789', status: 'active', assignedJeepneyId: jeepney._id, assignedRouteId: route._id });
    await Driver.create({ userId: otherDriverUser._id, status: 'active' });
    await Jeepney.updateOne({ _id: jeepney._id }, { currentDriverId: driver._id });
    await require('../../src/models/codingHoliday').create({ date: require('../../src/services/operatingRules.service').manilaDate(), name: 'Synthetic test exemption' });
    const app = require('../../src/app');
    await Promise.all(Object.values(mongoose.models).map(m => m.init()));
    apiServer = http.createServer(app);
    sockets.attachSocketServer(apiServer, { corsOrigins: [webOrigin] });
    const web = express();
    web.use(express.static(path.join(root, process.env.SYSTEM_TEST_BUILD_DIR || 'artifacts/reliability_staging_2026-10-07/admin-web')));
    webServer = http.createServer(web);
    await Promise.all([[apiServer, 5068], [webServer, 8768]].map(([s, port]) => new Promise((resolve, reject) => {
      s.once('error', reject); s.listen(port, '127.0.0.1', resolve);
    })));
    console.log('Loopback API and admin website ready');
    async function syntheticToken(user) {
      const sid = crypto.randomUUID();
      await AuthSession.create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 3600000) });
      return require('../../src/utils/jwt').signToken({ sub: String(user._id), role: user.role, sid });
    }
    return { apiOrigin, webOrigin, password, point, mailbox, stop, restartListener: async () => { await sockets.closeSocketServer(); await closeServer(apiServer); apiServer = http.createServer(app); sockets.attachSocketServer(apiServer, { corsOrigins: [webOrigin] }); await new Promise((resolve, reject) => { apiServer.once('error', reject); apiServer.listen(5068, '127.0.0.1', resolve); }); }, reconnectDatabase: async () => { await mongoose.disconnect(); await mongoose.connect(uri); }, models: { User, Passenger, Driver, Route, Jeepney, Trip },
      ids: { route: String(route._id), jeepney: String(jeepney._id), driver: String(driver._id), passenger: String(passenger._id) },
      accounts: { admin, driver: driverUser, otherDriver: otherDriverUser, passenger: passengerUser, otherPassenger: otherPassengerUser },
      adminToken: await syntheticToken(admin) };
  } catch (error) { await stop(); throw error; }
}
module.exports = { createLab, apiOrigin, webOrigin, point };
