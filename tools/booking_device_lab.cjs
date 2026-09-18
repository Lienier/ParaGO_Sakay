// Explicit local-only walkthrough harness. Never imports the live .env file.
const crypto = require('node:crypto');
const path = require('node:path');
const os = require('node:os');
require('dotenv').config = () => ({ parsed: {} });
Object.assign(process.env, {
  NODE_ENV: 'test', MONGO_URI: 'mongodb://127.0.0.1/unused', REDIS_URL: '',
  JWT_SECRET: crypto.randomBytes(48).toString('hex'),
  JWT_REFRESH_SECRET: crypto.randomBytes(48).toString('hex'),
  GROUP_BOOKINGS_ENABLED: 'true', RUN_API_JOBS: 'false',
  FIREBASE_PROJECT_ID: '', FIREBASE_CLIENT_EMAIL: '', FIREBASE_PRIVATE_KEY: '',
  TOMTOM_API_KEY: '', GOOGLE_ROUTES_API_KEY: '', GOOGLE_APPLICATION_CREDENTIALS: '',
});
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const express = require('express');
const http = require('node:http');

async function main() {
  const repl = await MongoMemoryReplSet.create({ binary: { version: '8.0.28', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  await mongoose.connect(repl.getUri('booking_device_lab'));
  const User = require('../src/models/user');
  const Passenger = require('../src/models/passenger');
  const Driver = require('../src/models/driver');
  const Jeep = require('../src/models/jeepney');
  const Route = require('../src/models/route');
  const Trip = require('../src/models/tripSession');
  const password = 'Booking-Lab-Only-2026!';
  const passwordHash = await require('bcryptjs').hash(password, 10);
  const passengerUser = await User.create({ email: 'passenger.booking@example.test', fullName: 'Local Booking Passenger', role: 'PASSENGER', passwordHash });
  await Passenger.create({ userId: passengerUser._id });
  const driverUser = await User.create({ email: 'driver.booking@example.test', fullName: 'Local Booking Driver', role: 'DRIVER', passwordHash });
  const point = lat => ({ type: 'Point', coordinates: [121.05, lat] });
  const route = await Route.create({ name: 'LOCAL TEST - Remote Pickup', code: 'LOCAL-LAB', direction: 'up',
    path: { type: 'LineString', coordinates: [[121.05, 14.90], [121.05, 14.93]] },
    stops: [{ name: 'Lab Start', order: 0, fare: 0, location: point(14.90) }, { name: 'Lab End', order: 1, fare: 20, location: point(14.93) }] });
  const jeep = await Jeep.create({ plateNumber: 'LAB 123', capacity: 6, lastKnownLocation: point(14.90), lastSeenAt: new Date() });
  const driver = await Driver.create({ userId: driverUser._id, status: 'active', assignedJeepneyId: jeep._id, assignedRouteId: route._id });
  await Trip.create({ driverId: driver._id, jeepneyId: jeep._id, routeId: route._id, status: 'active', operatingMode: 'route', acceptRequests: true });
  await require('../src/models/codingHoliday').create({ date: require('../src/services/operatingRules.service').manilaDate(), name: 'Isolated lab exemption' });
  const app = express(); app.use(express.json());
  app.get('/api/v1/health', (_req, res) => res.json({ status: 'ok', service: 'LOCAL BOOKING LAB ONLY' }));
  // Production authentication/ownership handlers, without Redis rate-limit middleware.
  // This loopback-only harness does not validate production rate limiting or delivery.
  app.use('/api/v1/auth', (req, res, next) => {
    if (/google|facebook|forgot|reset|admin|register/i.test(req.path)) return res.sendStatus(403);
    next();
  });
  require('../src/config/apiRoutes').registerApiRoutes(app, { prefix: '/api/v1' });
  app.use(require('../src/middlewares/error.middleware').errorHandler);
  const server = http.createServer(app);
  const sockets = require('../src/realtime/socketServer');
  sockets.attachSocketServer(server, { corsOrigins: [] });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(5057, '127.0.0.1', resolve); });
  console.log('LOCAL BOOKING LAB ready at http://127.0.0.1:5057/api/v1');
  console.log('Temporary accounts: passenger.booking@example.test / driver.booking@example.test');
  console.log('Password: Booking-Lab-Only-2026! (temporary database only)');
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => {
    await sockets.closeSocketServer(); server.close(); await mongoose.disconnect(); await repl.stop(); process.exit(0);
  });
}
main().catch(error => { console.error(error.message); process.exit(1); });
