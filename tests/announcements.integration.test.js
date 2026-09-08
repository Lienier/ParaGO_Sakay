const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const {
  after,
  before,
  beforeEach,
  test,
} = require('node:test');

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');
const request = require('supertest');

const app = require('../src/app');
const { mongoUri: configuredMongoUri } = require('../src/config/env');
const Announcement = require('../src/models/announcement');
const AnnouncementDismissal = require('../src/models/announcementDismissal');
const Notification = require('../src/models/notification');
const User = require('../src/models/user');
const {
  reconcileAnnouncementStatuses,
} = require('../src/services/announcement.service');
const { signToken } = require('../src/utils/jwt');

let memoryServer;
let admin;
let passenger;
let driver;
let adminToken;
let passengerToken;
let driverToken;

const isoFromNow = (milliseconds) =>
  new Date(Date.now() + milliseconds).toISOString();

const announcementPayload = (overrides = {}) => ({
  title: 'Service update',
  body: 'Normal service continues with a short delay.',
  category: 'service_change',
  severity: 'info',
  audiences: ['PASSENGER', 'DRIVER'],
  startsAt: isoFromNow(-60_000),
  expiresAt: isoFromNow(3_600_000),
  ...overrides,
});

const tokenFor = async (user) => {
  const sid = require('crypto').randomUUID();
  await require('../src/models/authSession').create({ _id: sid, userId: user._id,
    authVersion: user.authVersion || 0, expiresAt: new Date(Date.now() + 3600000) });
  return signToken({ sub: user._id.toString(), sid });
};

const createAnnouncement = async (overrides = {}) => {
  const response = await request(app)
    .post('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${adminToken}`)
    .send(announcementPayload(overrides));
  assert.equal(response.status, 201, response.text);
  return response.body.data;
};

before(async () => {
  memoryServer = await MongoMemoryServer.create({
    binary: {
      downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries'),
    },
    instance: { dbName: 'parago-announcements-integration' },
  });
  const memoryUri = memoryServer.getUri();
  assert.notEqual(memoryUri, configuredMongoUri);
  assert.match(memoryUri, /^mongodb:\/\/127\.0\.0\.1:/);
  await mongoose.connect(memoryUri);
});

after(async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  await memoryServer.stop();
});

beforeEach(async () => {
  await Promise.all([
    Announcement.deleteMany({}),
    AnnouncementDismissal.deleteMany({}),
    Notification.deleteMany({}),
    User.deleteMany({}),
  ]);
  [admin, passenger, driver] = await User.create([
    {
      email: 'announcement-admin@example.test',
      fullName: 'Announcement Admin',
      role: 'ADMIN',
      status: 'active',
    },
    {
      email: 'announcement-passenger@example.test',
      fullName: 'Announcement Passenger',
      role: 'PASSENGER',
      status: 'active',
    },
    {
      email: 'announcement-driver@example.test',
      fullName: 'Announcement Driver',
      role: 'DRIVER',
      status: 'active',
    },
  ]);
  adminToken = await tokenFor(admin);
  passengerToken = await tokenFor(passenger);
  driverToken = await tokenFor(driver);
});

test('authorization and audience targeting are enforced', async () => {
  await createAnnouncement({ audiences: ['PASSENGER'] });

  const passengerList = await request(app)
    .get('/api/v1/announcements/active')
    .set('Authorization', `Bearer ${passengerToken}`);
  assert.equal(passengerList.status, 200);
  assert.equal(passengerList.body.data.length, 1);

  const driverList = await request(app)
    .get('/api/v1/announcements/active')
    .set('Authorization', `Bearer ${driverToken}`);
  assert.equal(driverList.status, 200);
  assert.equal(driverList.body.data.length, 0);

  const adminActive = await request(app)
    .get('/api/v1/announcements/active')
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(adminActive.status, 403);

  const passengerAdminList = await request(app)
    .get('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${passengerToken}`);
  assert.equal(passengerAdminList.status, 403);
  assert.equal(await Notification.countDocuments(), 0);
});

test('critical publication and active archive require confirmations', async () => {
  const criticalPayload = announcementPayload({
    severity: 'critical',
    category: 'safety',
  });
  const rejected = await request(app)
    .post('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${adminToken}`)
    .send(criticalPayload);
  assert.equal(rejected.status, 400);

  const accepted = await request(app)
    .post('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ ...criticalPayload, confirmCritical: true });
  assert.equal(accepted.status, 201);

  const archivePath =
    `/api/v1/announcements/admin/${accepted.body.data.id}/archive`;
  const archiveRejected = await request(app)
    .post(archivePath)
    .set('Authorization', `Bearer ${adminToken}`)
    .send({});
  assert.equal(archiveRejected.status, 400);

  const archiveAccepted = await request(app)
    .post(archivePath)
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ confirmActiveArchive: true });
  assert.equal(archiveAccepted.status, 200);
  assert.equal(archiveAccepted.body.data.status, 'archived');

  const editable = await createAnnouncement();
  const criticalUpdateRejected = await request(app)
    .patch(`/api/v1/announcements/admin/${editable.id}`)
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ severity: 'critical' });
  assert.equal(criticalUpdateRejected.status, 400);
  const criticalUpdateAccepted = await request(app)
    .patch(`/api/v1/announcements/admin/${editable.id}`)
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ severity: 'critical', confirmCritical: true });
  assert.equal(criticalUpdateAccepted.status, 200);
  assert.equal(criticalUpdateAccepted.body.data.severity, 'critical');
});

test('dismissals are revision-specific and persist for the user', async () => {
  const created = await createAnnouncement({ audiences: ['PASSENGER'] });
  const dismissPath = `/api/v1/announcements/${created.id}/dismiss`;

  const missingRevision = await request(app)
    .post(dismissPath)
    .set('Authorization', `Bearer ${passengerToken}`)
    .send({});
  assert.equal(missingRevision.status, 400);

  const dismissed = await request(app)
    .post(dismissPath)
    .set('Authorization', `Bearer ${passengerToken}`)
    .send({ revision: 1 });
  assert.equal(dismissed.status, 200);

  const refreshedToken = await tokenFor(passenger);
  const hidden = await request(app)
    .get('/api/v1/announcements/active')
    .set('Authorization', `Bearer ${refreshedToken}`);
  assert.equal(hidden.body.data.length, 0);

  const updated = await request(app)
    .patch(`/api/v1/announcements/admin/${created.id}`)
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ body: 'Updated service information.' });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.data.revision, 2);

  const visibleAgain = await request(app)
    .get('/api/v1/announcements/active')
    .set('Authorization', `Bearer ${refreshedToken}`);
  assert.equal(visibleAgain.body.data.length, 1);
  assert.equal(visibleAgain.body.data[0].revision, 2);

  const staleDismissal = await request(app)
    .post(dismissPath)
    .set('Authorization', `Bearer ${passengerToken}`)
    .send({ revision: 1 });
  assert.equal(staleDismissal.status, 409);
  assert.equal(staleDismissal.body.errors[0].currentRevision, 2);

  const currentDismissal = await request(app)
    .post(dismissPath)
    .set('Authorization', `Bearer ${passengerToken}`)
    .send({ revision: 2 });
  assert.equal(currentDismissal.status, 200);
});

test('admin history is paginated, filtered, and bounded', async () => {
  const documents = Array.from({ length: 31 }, (_, index) => ({
    ...announcementPayload({
      title: `Announcement ${index + 1}`,
      category: index % 2 === 0 ? 'maintenance' : 'general',
    }),
    status: 'published',
    revision: 1,
    publishedAt: new Date(),
    createdByAdminId: admin._id,
    updatedByAdminId: admin._id,
  }));
  await Announcement.insertMany(documents);

  const secondPage = await request(app)
    .get('/api/v1/announcements/admin?page=2&limit=10')
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(secondPage.status, 200);
  assert.equal(secondPage.body.data.items.length, 10);
  assert.deepEqual(secondPage.body.data.pagination, {
    page: 2,
    limit: 10,
    total: 31,
    totalPages: 4,
  });

  const bounded = await request(app)
    .get('/api/v1/announcements/admin?page=1&limit=500')
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(bounded.status, 200);
  assert.equal(bounded.body.data.pagination.limit, 50);

  const filtered = await request(app)
    .get('/api/v1/announcements/admin?category=maintenance')
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(filtered.status, 200);
  assert.equal(filtered.body.data.pagination.total, 16);
});

test('timestamps, ranges, and expired lifecycle rules are enforced', async () => {
  const malformed = await request(app)
    .post('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${adminToken}`)
    .send(announcementPayload({ startsAt: 'July 28, 2026' }));
  assert.equal(malformed.status, 400);

  const impossibleDate = await request(app)
    .post('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${adminToken}`)
    .send(announcementPayload({ startsAt: '2026-02-30T10:00:00.000Z' }));
  assert.equal(impossibleDate.status, 400);

  for (const invalidPayload of [
    { category: 'weather' },
    { severity: 'emergency' },
    { audiences: [] },
    { title: '   ' },
    { body: '' },
  ]) {
    const invalid = await request(app)
      .post('/api/v1/announcements/admin')
      .set('Authorization', `Bearer ${adminToken}`)
      .send(announcementPayload(invalidPayload));
    assert.equal(invalid.status, 400);
  }

  const invalidRange = await request(app)
    .get(
      '/api/v1/announcements/admin' +
        '?from=2026-07-29T00:00:00.000Z&to=2026-07-28T00:00:00.000Z'
    )
    .set('Authorization', `Bearer ${adminToken}`);
  assert.equal(invalidRange.status, 400);

  const expired = await Announcement.create({
    ...announcementPayload({
      title: 'Expired original',
      startsAt: isoFromNow(-7_200_000),
      expiresAt: isoFromNow(-3_600_000),
    }),
    status: 'expired',
    revision: 4,
    createdByAdminId: admin._id,
    updatedByAdminId: admin._id,
  });
  const editExpired = await request(app)
    .patch(`/api/v1/announcements/admin/${expired._id}`)
    .set('Authorization', `Bearer ${adminToken}`)
    .send({ title: 'Changed expired record' });
  assert.equal(editExpired.status, 409);

  const duplicate = await request(app)
    .post('/api/v1/announcements/admin')
    .set('Authorization', `Bearer ${adminToken}`)
    .send(
      announcementPayload({
        title: expired.title,
        body: expired.body,
        startsAt: isoFromNow(3_600_000),
        expiresAt: isoFromNow(7_200_000),
      })
    );
  assert.equal(duplicate.status, 201);
  assert.equal(duplicate.body.data.revision, 1);
  assert.notEqual(duplicate.body.data.id, expired._id.toString());
  assert.equal((await Announcement.findById(expired._id)).revision, 4);
});

test('concurrent scheduler runs transition each record only once', async () => {
  await Announcement.create([
    {
      ...announcementPayload({
        title: 'Ready to publish',
        startsAt: isoFromNow(-60_000),
        expiresAt: isoFromNow(3_600_000),
      }),
      status: 'scheduled',
      revision: 1,
      createdByAdminId: admin._id,
      updatedByAdminId: admin._id,
    },
    {
      ...announcementPayload({
        title: 'Ready to expire',
        startsAt: isoFromNow(-7_200_000),
        expiresAt: isoFromNow(-60_000),
      }),
      status: 'published',
      revision: 1,
      publishedAt: new Date(Date.now() - 7_200_000),
      createdByAdminId: admin._id,
      updatedByAdminId: admin._id,
    },
  ]);

  const results = await Promise.all([
    reconcileAnnouncementStatuses(),
    reconcileAnnouncementStatuses(),
  ]);
  assert.equal(
    results.reduce((sum, item) => sum + item.published, 0),
    1
  );
  assert.equal(
    results.reduce((sum, item) => sum + item.expired, 0),
    1
  );

  const published = await Announcement.findOne({ title: 'Ready to publish' });
  const expired = await Announcement.findOne({ title: 'Ready to expire' });
  assert.equal(published.status, 'published');
  assert.ok(published.publishedAt);
  assert.equal(expired.status, 'expired');

  const passengerActive = await request(app)
    .get('/api/v1/announcements/active')
    .set('Authorization', `Bearer ${passengerToken}`);
  assert.equal(passengerActive.status, 200);
  assert.deepEqual(
    passengerActive.body.data.map((item) => item.title),
    ['Ready to publish']
  );
});
