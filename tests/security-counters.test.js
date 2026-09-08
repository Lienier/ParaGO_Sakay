const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { createApiRateLimiters } = require('../src/middlewares/rateLimits');
const { errorHandler } = require('../src/middlewares/error.middleware');
const { injectRedisClientForTests, resetRedisForTests } = require('../src/services/redis.service');
const { reserveAuthEmail } = require('../src/services/securityCounters.service');
const { signToken } = require('../src/utils/jwt');
afterEach(resetRedisForTests);

test('separate limiter instances share Redis counts and expose Retry-After', async () => {
  const counts = new Map();
  injectRedisClientForTests({ testClient: { isReady: true, eval: async (_script, { keys }) => {
    const count = (counts.get(keys[0]) || 0) + 1;
    counts.set(keys[0], count);
    return [count, 60000];
  } } });
  const first = express(); const second = express();
  first.get('/', createApiRateLimiters({ general: 2 }).general, (_req, res) => res.sendStatus(200));
  second.get('/', createApiRateLimiters({ general: 2 }).general, (_req, res) => res.sendStatus(200));
  const token = signToken({ sub: 'test-user', sid: 'test-session' });
  const call = (app) => request(app).get('/').set('Authorization', `Bearer ${token}`);
  assert.equal((await call(first)).status, 200);
  assert.equal((await call(second)).status, 200);
  const limited = await call(first);
  assert.equal(limited.status, 429);
  assert.equal(limited.headers['retry-after'], '60');
});

test('Redis outage fails closed for auth but permits bounded transportation fallback', async () => {
  resetRedisForTests();
  const app = express();
  const limits = createApiRateLimiters({ driverLocation: 1 });
  app.get('/login', limits.auth, (_req, res) => res.sendStatus(200));
  app.get('/refresh', limits.session, (_req, res) => res.sendStatus(200));
  app.get('/location', limits.driverLocation, (_req, res) => res.sendStatus(200));
  app.use(errorHandler);
  assert.equal((await request(app).get('/login')).status, 503);
  assert.equal((await request(app).get('/refresh')).status, 503);
  assert.equal((await request(app).get('/location')).status, 200);
  assert.equal((await request(app).get('/location')).status, 429);
});

test('email reservation rejects cooldown/quota and hides address in Redis keys', async () => {
  let script;
  let keys;
  injectRedisClientForTests({ testClient: { isReady: true, eval: async (value, options) => {
    script = value; keys = options.keys; return 42000;
  } } });
  await assert.rejects(reserveAuthEmail('user@example.test'), (error) => error.statusCode === 429 && error.retryAfter === 42);
  assert.ok(keys.every((key) => !key.includes('user@example.test')));
  assert.match(script, />=5/);
  assert.match(script, />=1000/);
  assert.match(script, /60000/);
  resetRedisForTests();
  await assert.rejects(reserveAuthEmail('user@example.test'), (error) => error.statusCode === 503);
});
