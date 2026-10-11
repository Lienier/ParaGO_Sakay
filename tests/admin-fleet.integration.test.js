require('dotenv').config = () => ({ parsed: {} });
Object.assign(process.env, { NODE_ENV: 'test', DEPLOYMENT_ENV: 'test', REDIS_URL: '',
  MONGO_URI: 'mongodb://127.0.0.1/unused_fleet_test',
  JWT_SECRET: 'isolated-fleet-secret', JWT_REFRESH_SECRET: 'isolated-fleet-refresh-secret',
  AUTH_EMAIL_ENABLED: 'false', RUN_API_JOBS: 'false', AUTOMATIC_GROUP_FLOW_ENABLED: 'false',
  AUTOMATIC_DRIVER_LIFECYCLE_ENABLED: 'false', ASYNC_LOCATION_PROCESSING_ENABLED: 'false' });
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path'), os = require('node:os'), crypto = require('node:crypto');
const mongoose = require('mongoose'), request = require('supertest');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { io } = require('socket.io-client');
const { FleetLocationBatcher } = require('../src/realtime/fleetLocationBatcher');
const User = require('../src/models/user'), Driver = require('../src/models/driver');
const Jeep = require('../src/models/jeepney'), Route = require('../src/models/route');
const sockets = require('../src/realtime/socketServer');
let db, server, origin, adminToken, driverToken, passengerToken, jeep, route;
const clients = [];
async function token(role) {
  const user = await User.create({ email: `${crypto.randomUUID()}@fleet.test`, fullName: `${role} synthetic`, role, status: 'active' });
  const sid = crypto.randomUUID();
  await require('../src/models/authSession').create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 3600000) });
  return { user, token: require('../src/utils/jwt').signToken({ sub: String(user._id), sid }) };
}
before(async () => {
  db = await MongoMemoryServer.create({ binary: { version: '8.2.6', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') } });
  const uri = db.getUri('admin_fleet_isolated');
  assert.match(uri, /^mongodb:\/\/127\.0\.0\.1:/);
  await mongoose.connect(uri);
  const admin = await token('ADMIN'), driver = await token('DRIVER'), passenger = await token('PASSENGER');
  adminToken = admin.token; driverToken = driver.token; passengerToken = passenger.token;
  route = await Route.create({ name: 'Synthetic route', code: 'FLEET-TEST', status: 'active' });
  const profile = await Driver.create({ userId: driver.user._id, status: 'active', assignedRouteId: route._id });
  const rows = await Jeep.insertMany(Array.from({ length: 100 }, (_, i) => ({ plateNumber: `TEST ${String(i).padStart(3, '0')}`, capacity: 20,
    ...(i === 0 ? { currentDriverId: profile._id } : {}),
    ...(i < 99 ? { lastKnownLocation: { type: 'Point', coordinates: [121.05, 14.9 + i / 10000] }, lastSeenAt: new Date(Date.now() - i * 1000) } : {}) })));
  jeep = rows[0]; profile.assignedJeepneyId = jeep._id; await profile.save();
  server = require('node:http').createServer(require('../src/app')); sockets.attachSocketServer(server);
  server.listen(0, '127.0.0.1'); await new Promise(r => server.once('listening', r));
  origin = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { clients.forEach(c => c.disconnect()); await sockets.closeSocketServer();
  if (server?.listening) await new Promise(r => server.close(r)); await mongoose.disconnect(); await db?.stop(); });
async function connect(token) {
  const c = io(origin, { transports: ['websocket'], auth: { token }, reconnection: false }); clients.push(c);
  await new Promise((resolve, reject) => { c.once('socket.ready', resolve); c.once('connect_error', reject); }); return c;
}
test('Admin snapshot includes all 100 vehicles, idle assigned route/driver, missing GPS and no account secrets', async () => {
  const result = await request(origin).get('/api/v1/admin/fleet').auth(adminToken, { type: 'bearer' });
  assert.equal(result.status, 200); assert.equal(result.headers['cache-control'], 'no-store');
  assert.equal(result.body.data.vehicles.length, 100);
  const first = result.body.data.vehicles.find(v => v.jeepneyId === String(jeep._id));
  assert.equal(first.routeId, String(route._id)); assert.equal(first.driverName, 'DRIVER synthetic'); assert.equal(first.tripId, '');
  assert.equal(result.body.data.vehicles.at(-1).latitude, null);
  assert.ok(!JSON.stringify(result.body).includes('passwordHash')); assert.ok(!JSON.stringify(result.body).includes('@fleet.test'));
});
test('fleet endpoint refuses unauthenticated users, passengers and drivers', async () => {
  assert.equal((await request(origin).get('/api/v1/admin/fleet')).status, 401);
  for (const token of [driverToken, passengerToken]) assert.equal((await request(origin).get('/api/v1/admin/fleet').auth(token, { type: 'bearer' })).status, 403);
});
test('accepted idle driver GPS reaches only Admin fleet sockets, with ordering metadata and no trip required', async () => {
  const admin = await connect(adminToken), driver = await connect(driverToken), passenger = await connect(passengerToken);
  let unauthorized = 0; for (const c of [driver, passenger]) c.on('fleet.locations.updated', () => unauthorized++);
  const event = new Promise((resolve, reject) => { const timer = setTimeout(() => reject(Error('Fleet event timeout')), 5000);
    admin.once('fleet.locations.updated', v => { clearTimeout(timer); resolve(v); }); });
  const at = new Date().toISOString(), streamId = crypto.randomUUID();
  const res = await request(origin).patch('/api/v1/drivers/me/location').auth(driverToken, { type: 'bearer' })
    .send({ latitude: 14.911, longitude: 121.051, accuracyMeters: 5, speedMetersPerSecond: 2, streamId, sequence: 1, capturedAt: at });
  assert.equal(res.status, 200, res.text);
  const payload = await event; assert.equal(payload.vehicles[0].jeepneyId, String(jeep._id));
  assert.equal(payload.vehicles[0].latitude, 14.911); assert.equal(payload.vehicles[0].sequence, 1);
  assert.equal(payload.vehicles[0].routeId, String(route._id)); assert.equal(unauthorized, 0);
  const stale = await request(origin).patch('/api/v1/drivers/me/location').auth(driverToken, { type: 'bearer' })
    .send({ latitude: 14.912, longitude: 121.051, accuracyMeters: 5, speedMetersPerSecond: 2, streamId, sequence: 1, capturedAt: at });
  assert.equal(stale.status, 409);
});
test('fleet batching preserves 100 vehicles, coalesces repeated updates, rejects invalid GPS and never regresses pending timestamps', () => {
  const batches = [], batcher = new FleetLocationBatcher({ autoStart: false, maxBatchSize: 100, onBatch: b => batches.push(b) });
  const now = new Date().toISOString();
  for (let i = 0; i < 100; i++) batcher.enqueue({ jeepneyId: `j-${i}`, latitude: 14.9, longitude: 121.05, lastSeenAt: now });
  assert.equal(batches[0].vehicles.length, 100);
  for (let i = 0; i < 50; i++) batcher.enqueue({ jeepneyId: 'j-1', latitude: 14.9 + i / 10000, longitude: 121.05, lastSeenAt: now });
  assert.equal(batcher.enqueue({ jeepneyId: 'j-1', latitude: 14.8, longitude: 121.05, lastSeenAt: '2020-01-01' }), false);
  assert.equal(batcher.enqueue({ jeepneyId: 'bad', latitude: null, longitude: 121.05, lastSeenAt: now }), false);
  batcher.flush(); assert.equal(batches[1].vehicles.length, 1); assert.equal(batches[1].vehicles[0].latitude, 14.9049); batcher.stop();
});
