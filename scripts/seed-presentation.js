// Explicit targets only. Never starts application jobs or contacts clients.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
mongoose.set('autoIndex', false);
const modelNames = ['User', 'Admin', 'Driver', 'Passenger', 'Route', 'Jeepney',
  'TripSession', 'PickupRequest', 'RideSession', 'Announcement', 'Notification',
  'SupportThread', 'SupportMessage'];
const models = Object.fromEntries(modelNames.map(name => [name,
  require(`../src/models/${name[0].toLowerCase()}${name.slice(1)}`)]));
const id = label => new mongoose.Types.ObjectId(crypto.createHash('sha256')
  .update(`sakay-presentation-v1:${label}`).digest('hex').slice(0, 24));
const point = coordinates => ({ type: 'Point', coordinates });

function options(args = process.argv.slice(2)) {
  const allowed = ['--apply', '--staging', '--live', '--date=', '--lat=', '--lng=', '--admin-email='];
  if (args.some(arg => !allowed.some(flag => flag.endsWith('=') ? arg.startsWith(flag) : arg === flag))) {
    throw Error('Unknown option. Use --apply, --staging/--live, --date=YYYY-MM-DD, --lat=..., --lng=..., --admin-email=...');
  }
  const value = (key, fallback) => args.find(arg => arg.startsWith(`--${key}=`))?.slice(key.length + 3) ?? fallback;
  const date = value('date', new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10));
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(`${date}T00:00:00+08:00`)) ||
      new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) !== date) throw Error('Invalid presentation date');
  const lat = Number(value('lat', '14.9000')), lng = Number(value('lng', '121.0500'));
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 89 || Math.abs(lng) > 179) throw Error('Invalid terminal coordinates');
  const adminEmail = value('admin-email', 'admin.presentation@example.test').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(adminEmail)) throw Error('Invalid admin email');
  const live = args.includes('--live'), staging = args.includes('--staging');
  if (live && staging) throw Error('Choose one destination');
  if (live && ['lat', 'lng', 'admin-email'].some(key => !args.some(arg => arg.startsWith(`--${key}=`)))) {
    throw Error('Live presentation requires explicit --lat, --lng and an existing --admin-email');
  }
  return { apply: args.includes('--apply'), staging, live, date, lat, lng, adminEmail };
}

async function buildDataset(opts, password) {
  const rows = Object.fromEntries(modelNames.map(name => [name, []]));
  const start = new Date(`${opts.date}T00:00:00+08:00`);
  const prior = new Date(start.getTime() - 86400000);
  const add = (name, key, fields) => {
    const doc = new models[name]({ _id: id(key), createdAt: prior, updatedAt: prior, ...fields });
    const error = doc.validateSync();
    if (error) throw error;
    const row = doc.toObject(); rows[name].push(row); return row;
  };
  const hash = await bcrypt.hash(password, 11);
  const account = (key, role, email, fullName) => add('User', `user:${key}`, {
    email, fullName, role, passwordHash: hash, status: 'active', isVerified: true,
    legalAcceptance: { termsVersion: '2026-10-03', privacyVersion: '2026-10-03', acceptedAt: prior },
  });
  const admin = account('admin', 'ADMIN', opts.adminEmail, 'Presentation Administrator');
  add('Admin', 'admin', { userId: admin._id, notes: 'Synthetic presentation account' });
  const routes = [0, 1].map(index => {
    // Both routes begin at the chosen presentation venue. Synthetic geometry, not a public route.
    const coordinates = [0, 1, 2, 3].map(stop => [opts.lng + stop * .004, opts.lat + stop * (index ? -.003 : .003)]);
    const prefix = `DEMO-${index + 1}`;
    return add('Route', `route:${index}`, { name: `Presentation ${index ? 'South' : 'North'} Route`, code: prefix,
      direction: 'up', status: 'active', description: 'Synthetic presentation route; not public transport guidance.',
      path: { type: 'LineString', coordinates }, navigation: { source: 'cached' },
      stops: coordinates.map((coords, stop) => ({ name: stop ? `Demo Stop ${stop}` : 'Presentation Terminal',
        code: `${prefix}-S${stop + 1}`, order: stop + 1, fare: stop ? 17 + (stop - 1) * 2 : 0, location: point(coords) })),
      terminal: { enabled: true, name: 'Presentation Terminal', stopRef: `${prefix}-S1`, location: point(coordinates[0]), radiusMeters: 75 },
    });
  });
  const drivers = [0, 1, 2].map(index => {
    const user = account(`driver:${index}`, 'DRIVER', `driver${index + 1}.presentation@example.test`, `Presentation Driver ${index + 1}`);
    const jeepney = add('Jeepney', `jeepney:${index}`, { plateNumber: `DEMO 10${index + 1}`, capacity: 16,
      jeepneyName: `Presentation Jeepney ${index + 1}`, status: 'active', currentDriverId: id(`driver:${index}`) });
    return add('Driver', `driver:${index}`, { userId: user._id, employeeNumber: `DEMO-D${index + 1}`,
      licenseNumber: `DEMO-LICENSE-${index + 1}`, status: 'active', assignedJeepneyId: jeepney._id,
      assignedRouteId: routes[index % 2]._id, operatingMode: 'route', terminalQueueStatus: 'off_queue' });
  });
  const passengers = Array.from({ length: 6 }, (_, index) => {
    const user = account(`passenger:${index}`, 'PASSENGER', `passenger${index + 1}.presentation@example.test`, `Presentation Passenger ${index + 1}`);
    return add('Passenger', `passenger:${index}`, { userId: user._id, defaultRouteId: routes[index % 2]._id,
      savedPlaces: [{ name: 'Presentation Terminal', key: 'demo-terminal', lat: opts.lat, lng: opts.lng }] });
  });
  for (let day = 1; day <= 7; day++) {
    const driver = drivers[(day - 1) % 3], route = routes[(day - 1) % 3 % 2];
    const startedAt = new Date(start.getTime() - day * 86400000 + 9 * 3600000);
    const endedAt = new Date(startedAt.getTime() + 45 * 60000);
    const key = `history:${opts.date}:${day}`;
    const trip = add('TripSession', key, { jeepneyId: driver.assignedJeepneyId, driverId: driver._id, routeId: route._id,
      status: 'completed', active: false, acceptRequests: false, startedAt, endedAt, occupancyCount: 0,
      manualOccupancyCount: 0, operatingMode: 'route', terminalQueueStatus: 'off_queue', routePathSnapshot: route.path,
      notes: 'Synthetic completed presentation trip', createdAt: startedAt, updatedAt: endedAt });
    for (let rideIndex = 0; rideIndex < 3; rideIndex++) {
      const passenger = passengers[(day + rideIndex) % passengers.length];
      const boarding = route.stops[0], destination = route.stops[rideIndex + 1], partySize = rideIndex + 1;
      const fareSnapshot = { boardingStopRef: boarding.code, boardingStopOrder: boarding.order, boardingFare: boarding.fare,
        destinationStopRef: destination.code, destinationStopOrder: destination.order, destinationFare: destination.fare, amount: destination.fare };
      const pickup = add('PickupRequest', `${key}:pickup:${rideIndex}`, { passengerId: passenger._id, tripSessionId: trip._id,
        routeId: route._id, stopRef: boarding.code, pickupLocation: boarding.location, destinationStopRef: destination.code,
        destinationLocation: destination.location, pickupType: 'roadside', fareSnapshot, partySize, status: 'completed',
        acknowledgedBy: driver._id, acknowledgedAt: startedAt, sourceNote: 'Synthetic completed presentation booking',
        // Production TTL deletes completed bookings too. Keep these synthetic history references through the demo week.
        expiresAt: new Date(start.getTime() + 7 * 86400000), createdAt: startedAt, updatedAt: endedAt });
      add('RideSession', `${key}:ride:${rideIndex}`, { passengerId: passenger._id, tripSessionId: trip._id, pickupRequestId: pickup._id,
        boardingStopRef: boarding.code, boardingLocation: boarding.location, destinationStopRef: destination.code,
        destinationLocation: destination.location, fareSnapshot, partySize, boardedCount: partySize, remainingCount: 0,
        regularTotal: partySize * destination.fare, status: 'completed', boardedAt: startedAt, endedAt,
        offboardingMethod: 'manual', completedByUserId: driver.userId, completedByRole: 'driver', canSendStopAlert: false,
        createdAt: startedAt, updatedAt: endedAt });
    }
  }
  add('Announcement', 'announcement', { title: 'Welcome to the SAKAY presentation', body: 'This environment contains sample transportation data.',
    category: 'general', severity: 'info', audiences: ['PASSENGER', 'DRIVER'], status: 'published', startsAt: prior,
    publishedAt: prior, expiresAt: new Date(start.getTime() + 7 * 86400000), createdByAdminId: admin._id, updatedByAdminId: admin._id });
  passengers.forEach((passenger, index) => add('Notification', `notification:${index}`, { userId: passenger.userId,
    type: 'presentation', title: 'Welcome to SAKAY', body: 'Your presentation account is ready.', category: 'general',
    isRead: index % 2 === 0, ...(index % 2 === 0 ? { readAt: prior } : {}) }));
  [passengers[0], drivers[0]].forEach((profile, index) => {
    const body = index ? 'Please confirm my assigned route for the demonstration.' : 'How do I book a ride?';
    const role = index ? 'DRIVER' : 'PASSENGER';
    const trip = rows.TripSession.find(row => String(row.driverId) === String(drivers[0]._id));
    const thread = add('SupportThread', `thread:${index}`, { userId: profile.userId, userRole: role, assignedAdminId: admin._id,
      subject: index ? 'Route assignment' : 'Booking help', category: 'general_help', status: 'awaiting_admin',
      routeId: routes[0]._id, ...(index ? { tripSessionId: trip._id } : {}), lastMessageAt: prior,
      lastMessagePreview: body, lastMessageSenderRole: role, unreadAdminCount: 1, unreadUserCount: 0 });
    add('SupportMessage', `message:${index}`, { threadId: thread._id, senderId: profile.userId, senderRole: role, body });
  });
  return rows;
}

function localBoundary(uri) {
  const { parseMongoTarget } = require('./start-staging');
  const target = parseMongoTarget(uri, 'DEMO_MONGO_URI');
  if (!uri.startsWith('mongodb://') || target.database !== 'sakay_presentation' ||
      !target.host.split(',').every(host => /^(127\.0\.0\.1|localhost)(:\d+)?$/.test(host))) {
    throw Error('Local seed requires loopback MongoDB and database sakay_presentation');
  }
  return uri;
}

async function applyDataset(rows, { ensureIndexes = false } = {}) {
  // Reject an existing unrelated record with a colliding natural key before inserting anything.
  for (const [name, field] of [['User', 'email'], ['Route', 'code'], ['Jeepney', 'plateNumber']]) {
    for (const row of rows[name]) {
      const existing = await models[name].findOne({ [field]: row[field] }).select('_id').lean();
      if (existing && String(existing._id) !== String(row._id)) throw Error(`Existing ${name} ${field} collision; choose a separate demo database/account`);
    }
  }
  for (const [name, docs] of Object.entries(rows)) {
    if (!docs.length) continue;
    await models[name].createCollection();
    if (ensureIndexes) await models[name].createIndexes();
  }
  const session = await mongoose.startSession();
  let inserted = 0;
  try {
    await session.withTransaction(async () => {
      inserted = 0;
      for (const [name, docs] of Object.entries(rows)) {
        const result = await models[name].bulkWrite(docs.map(doc => ({ updateOne: {
          filter: { _id: doc._id }, update: { $setOnInsert: doc }, upsert: true, timestamps: false,
        } })), { session, timestamps: false });
        inserted += result.upsertedCount;
      }
    });
  } finally { await session.endSession(); }
  return inserted;
}

async function useExistingAdmin(rows, email) {
  const admin = await models.User.findOne({ email, role: 'ADMIN', status: 'active' }).select('_id').lean();
  if (!admin) throw Error('An existing active ADMIN account with this email is required for live seeding');
  rows.User = rows.User.filter(user => user.role !== 'ADMIN');
  rows.Admin = [];
  for (const row of rows.Announcement) {
    row.createdByAdminId = admin._id;
    row.updatedByAdminId = admin._id;
  }
  for (const row of rows.SupportThread) row.assignedAdminId = admin._id;
}

function destination(opts) {
  if (opts.staging) return require('./phase10-safety').loadStagingBoundary().stagingUri;
  if (!opts.live) return localBoundary(process.env.DEMO_MONGO_URI || '');
  const { readEnvironmentFile, parseMongoTarget } = require('./start-staging');
  const values = readEnvironmentFile(path.resolve(__dirname, '../.env'));
  const uri = values.MONGO_URI || values.MONGODB_URI;
  parseMongoTarget(uri, 'Live MONGO_URI');
  return uri;
}

async function main() {
  const opts = options();
  const preview = await buildDataset(opts, 'Preview-Only-Not-Saved-2026!');
  if (opts.live) { preview.User = preview.User.filter(user => user.role !== 'ADMIN'); preview.Admin = []; }
  console.log(JSON.stringify({ mode: opts.apply ? 'apply' : 'preview: no database accessed',
    target: opts.live ? 'live target from .env; existing admin will be reused' : opts.staging ? 'guarded parago_staging' : 'local sakay_presentation', date: opts.date,
    terminal: { lat: opts.lat, lng: opts.lng }, counts: Object.fromEntries(Object.entries(preview).map(([key, rows]) => [key, rows.length])) }, null, 2));
  if (!opts.apply) return;
  const uri = destination(opts);
  const manifestPath = path.resolve(__dirname, `../.secure-backups/presentation-${opts.live ? 'live' : opts.staging ? 'staging' : 'local'}-accounts.json`);
  const manifest = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : {
    sharedPassword: `${crypto.randomBytes(15).toString('base64url')}!Aa9`, adminEmail: opts.adminEmail,
    targetFingerprint: crypto.createHash('sha256').update(uri).digest('hex'),
  };
  if (manifest.adminEmail !== opts.adminEmail || manifest.targetFingerprint !== crypto.createHash('sha256').update(uri).digest('hex')) {
    throw Error('Saved account manifest belongs to another target/admin email. Preserve it and use the original target/options.');
  }
  const rows = await buildDataset(opts, manifest.sharedPassword);
  try {
    await mongoose.connect(uri, { autoIndex: false, serverSelectionTimeoutMS: 10000 });
    const hello = await mongoose.connection.db.admin().command({ hello: 1 });
    if (!hello.setName && hello.msg !== 'isdbgrid') throw Error('MongoDB replica set is required for the transaction');
    if (opts.live) await useExistingAdmin(rows, opts.adminEmail);
    Object.assign(manifest, { date: opts.date, accounts: rows.User.map(user => ({ email: user.email, role: user.role })),
      existingAdmin: opts.live ? opts.adminEmail : undefined,
      seededIds: Object.fromEntries(Object.entries(rows).map(([name, docs]) => [name, docs.map(row => String(row._id))])),
      note: 'Shared password applies to the listed synthetic accounts only. Existing admin keeps its credentials and normal email OTP.' });
    fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', { mode: 0o600 });
    console.log(`Inserted ${await applyDataset(rows)} records. Existing demo records were retained.`);
    console.log(`Account/password file: ${manifestPath}`);
  } finally { await mongoose.disconnect(); }
}
if (require.main === module) main().catch(error => {
  // Avoid connection errors echoing credentials/hosts from the target URI.
  console.error(`Presentation seed failed (${error.name}): ${/Mongo/.test(error.name) ? 'Database connection/write failed; check target and replica-set configuration.' : error.message}`);
  process.exitCode = 1;
});
module.exports = { options, buildDataset, applyDataset, localBoundary, useExistingAdmin, models };
