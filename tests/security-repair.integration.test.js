const { before, after, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const bcrypt = require('bcryptjs');
const request = require('supertest');
const email = require('../src/services/authEmail.service');
const counters = require('../src/services/securityCounters.service');
const sent = [];
let emailUnavailable = false;
let deliveryFails = false;
// Isolated delivery boundary: no SES calls or real emails in tests.
email.ensureAuthEmailAvailable = async () => {
  if (emailUnavailable) throw new (require('../src/utils/apiError'))(503, 'Email authentication is temporarily unavailable');
};
email.sendAuthEmail = async (message) => {
  if (deliveryFails) throw new (require('../src/utils/apiError'))(503, 'Email authentication is temporarily unavailable');
  sent.push(message);
};
counters.reserveAuthEmail = async () => {};
const auth = require('../src/services/auth.service');
const User = require('../src/models/user');
const AuthSession = require('../src/models/authSession');
const Challenge = require('../src/models/adminLoginChallenge');
const { signToken, verifyAccessToken, verifyRefreshToken } = require('../src/utils/jwt');
const { requireSession, revokeSessions } = require('../src/services/sessionSecurity.service');
const app = require('../src/app');
let repl;
let admin;
let passenger;
const password = 'Secure-test-password-42';
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') },
    replSet: { count: 1, storageEngine: 'wiredTiger' } });
  await mongoose.connect(repl.getUri());
  const passwordHash = await bcrypt.hash(password, 4);
  [admin, passenger] = await User.create([
    { email: 'admin@example.test', fullName: 'Admin', role: 'ADMIN', passwordHash },
    { email: 'passenger@example.test', fullName: 'Passenger', role: 'PASSENGER', passwordHash },
  ]);
  await Promise.all(Object.values(mongoose.models).map((model) => model.init()));
});
after(async () => { await mongoose.disconnect(); if (repl) await repl.stop(); });

test('password-only admin login is blocked even when role is omitted', async () => {
  for (const role of [undefined, 'ADMIN']) {
    await assert.rejects(auth.loginEmail({ email: admin.email, password, role }), /email verification/);
  }
});

test('social login cannot silently link an existing admin account', async (t) => {
  const { OAuth2Client } = require('google-auth-library');
  const config = require('../src/config/env');
  const previous = [...config.googleClientIds];
  config.googleClientIds.push('isolated-test-client');
  t.after(() => config.googleClientIds.splice(0, config.googleClientIds.length, ...previous));
  t.mock.method(OAuth2Client.prototype, 'verifyIdToken', async () => ({
    getPayload: () => ({ sub: 'external-test-user', email: admin.email, name: 'Admin', email_verified: true }),
  }));
  await assert.rejects(auth.socialLogin({ provider: 'google', token: 'isolated-test-token' }), /existing sign-in method/);
  assert.equal((await User.findById(admin._id)).authProvider, 'local');
});

test('email OTP is single-use under concurrent verification and has no response code', async () => {
  const challenge = await auth.startAdminLoginOtp({ email: admin.email, password });
  assert.equal(challenge.maskedEmail, 'a***@example.test');
  assert.equal(challenge.code, undefined);
  const code = sent.at(-1).text.match(/\b\d{6}\b/)[0];
  const record = await Challenge.findById(challenge.challengeId);
  assert.notEqual(record.codeHash, crypto.createHash('sha256').update(code).digest('hex'));
  const results = await Promise.allSettled([1, 2].map(() => auth.verifyAdminLoginOtp({ challengeId: challenge.challengeId, code })));
  assert.equal(results.filter((item) => item.status === 'fulfilled').length, 1);
});

test('OTP resend invalidates prior challenge; attempts cannot exceed five', async () => {
  const old = await auth.startAdminLoginOtp({ email: admin.email, password });
  const oldCode = sent.at(-1).text.match(/\b\d{6}\b/)[0];
  const current = await auth.startAdminLoginOtp({ email: admin.email, password });
  await assert.rejects(auth.verifyAdminLoginOtp({ challengeId: old.challengeId, code: oldCode }), /Invalid/);
  const realCode = sent.at(-1).text.match(/\b\d{6}\b/)[0];
  const wrong = realCode === '000000' ? '111111' : '000000';
  await Promise.allSettled(Array.from({ length: 10 }, () => auth.verifyAdminLoginOtp({ challengeId: current.challengeId, code: wrong })));
  assert.equal((await Challenge.findById(current.challengeId)).attempts, 5);
  await assert.rejects(auth.verifyAdminLoginOtp({ challengeId: current.challengeId, code: realCode }), /Invalid/);
});

test('tokens are unique, purpose-bound and legacy tokens are rejected', () => {
  const claims = { sub: String(passenger._id), sid: crypto.randomUUID() };
  const first = signToken(claims, 'refresh');
  assert.notEqual(first, signToken(claims, 'refresh'));
  assert.throws(() => verifyAccessToken(first));
  assert.throws(() => verifyRefreshToken(signToken(claims)));
  assert.throws(() => verifyAccessToken(signToken({ sub: claims.sub })));
});

test('expired OTP cannot issue a session', async () => {
  const challenge = await auth.startAdminLoginOtp({ email: admin.email, password });
  const code = sent.at(-1).text.match(/\b\d{6}\b/)[0];
  await Challenge.updateOne({ _id: challenge.challengeId }, { $set: { expiresAt: new Date(Date.now() - 1000) } });
  await assert.rejects(auth.verifyAdminLoginOtp({ challengeId: challenge.challengeId, code }), /Invalid/);
});

test('reset responses are generic and general email outages apply to unknown accounts too', async () => {
  assert.deepEqual(await auth.requestPasswordReset({ email: 'missing@example.test' }), { delivered: true });
  emailUnavailable = true;
  try {
    for (const address of [passenger.email, 'missing@example.test']) {
      await assert.rejects(auth.requestPasswordReset({ email: address }), (error) => error.statusCode === 503);
    }
  } finally { emailUnavailable = false; }
});

test('failed reset delivery invalidates the undelivered token', async () => {
  const Reset = require('../src/models/passwordResetToken');
  const before = await Reset.countDocuments({ userId: passenger._id });
  deliveryFails = true;
  try {
    await assert.rejects(auth.requestPasswordReset({ email: passenger.email }), (error) => error.statusCode === 503);
  } finally { deliveryFails = false; }
  assert.equal(await Reset.countDocuments({ userId: passenger._id }), before + 1);
  assert.ok((await Reset.findOne({ userId: passenger._id }).sort({ createdAt: -1 })).usedAt);
});

test('refresh rotation allows exactly one concurrent success and logout revokes access', async () => {
  const initial = await auth.loginEmail({ email: passenger.email, password });
  const results = await Promise.allSettled([1, 2].map(() => auth.refreshSession({ refreshToken: initial.refreshToken })));
  const successes = results.filter((result) => result.status === 'fulfilled');
  assert.equal(successes.length, 1);
  const next = successes[0].value;
  assert.equal(verifyRefreshToken(next.refreshToken).exp, verifyRefreshToken(initial.refreshToken).exp);
  await auth.logoutSession({ refreshToken: next.refreshToken });
  await assert.rejects(requireSession(verifyAccessToken(next.token)), /no longer active/);
});

test('reset sends a fragment link, returns no secret and consumes it once', async () => {
  const initial = await auth.loginEmail({ email: passenger.email, password });
  const response = await auth.requestPasswordReset({ email: passenger.email });
  assert.deepEqual(response, { delivered: true });
  const token = sent.at(-1).text.match(/#([a-f0-9]{64})/)[1];
  const results = await Promise.allSettled([1, 2].map(() => auth.resetPassword({ token, newPassword: 'Replacement-password-42' })));
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  await assert.rejects(requireSession(verifyAccessToken(initial.token)), /no longer active/);
  const relogin = await auth.loginEmail({ email: passenger.email, password: 'Replacement-password-42' });
  await requireSession(verifyAccessToken(relogin.token));
});

test('report bounds are rejected and reset page uses restrictive browser headers', async () => {
  const sid = crypto.randomUUID();
  await AuthSession.create({ _id: sid, userId: admin._id, authVersion: 0, expiresAt: new Date(Date.now() + 60000) });
  const token = signToken({ sub: String(admin._id), sid });
  const response = await request(app).get('/api/v1/reports/passenger-flow?from=1900-01-01&to=2026-01-01').set('Authorization', `Bearer ${token}`);
  assert.equal(response.status, 400);
  const page = await request(app).get('/reset-password');
  assert.equal(page.status, 200);
  assert.equal(page.headers['cache-control'], 'no-store');
  assert.match(page.headers['content-security-policy'], /frame-ancestors 'none'/);
});
