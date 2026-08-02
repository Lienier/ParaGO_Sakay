const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const express = require('express');
const request = require('supertest');

const app = require('../src/app');
const { signToken } = require('../src/utils/jwt');
const { createCorsOriginDelegate } = require('../src/utils/cors');
const {
  createApiRateLimiters,
} = require('../src/middlewares/rateLimits');
const {
  requestContext,
  createStructuredHttpLogger,
} = require('../src/middlewares/requestContext');
const {
  createShutdownController,
  withTimeout,
} = require('../src/runtime/gracefulShutdown');

const root = path.resolve(__dirname, '..');

test('Express trusts exactly one reverse proxy hop', () => {
  const trust = app.get('trust proxy fn');
  assert.equal(trust('127.0.0.1', 0), true);
  assert.equal(trust('10.0.0.2', 1), false);
});

test('security headers and validated request IDs are returned', async () => {
  const suppliedRequestId = 'phase9-request-1234';
  const response = await request(app)
    .get('/health')
    .set('X-Request-Id', suppliedRequestId);
  assert.equal(response.status, 200);
  assert.equal(response.headers['x-request-id'], suppliedRequestId);
  assert.equal(response.headers['x-powered-by'], undefined);
  assert.equal(response.headers['x-content-type-options'], 'nosniff');

  const replaced = await request(app)
    .get('/health')
    .set('X-Request-Id', 'bad');
  assert.notEqual(replaced.headers['x-request-id'], 'bad');
  assert.match(replaced.headers['x-request-id'], /^[0-9a-f-]{36}$/);
});

test('request size is bounded and unknown routes do not echo query secrets',
    async () => {
  const oversized = await request(app)
    .post('/api/v1/unknown')
    .send({ content: 'x'.repeat(1024 * 1024 + 1) });
  assert.equal(oversized.status, 413);
  assert.equal(typeof oversized.headers['x-request-id'], 'string');

  const missing = await request(app)
    .get('/api/v1/unknown?token=must-not-be-echoed&lat=14.6');
  assert.equal(missing.status, 404);
  assert.doesNotMatch(JSON.stringify(missing.body), /must-not-be-echoed|14\.6/);
});

test('production CORS allowlist accepts configured web and originless clients',
    async () => {
  const delegate = createCorsOriginDelegate({
    allowedOrigins: ['https://admin.parago.example'],
  });
  const evaluate = (origin) =>
    new Promise((resolve) => delegate(origin, (error, allowed) => {
      resolve({ error, allowed });
    }));

  assert.deepEqual(await evaluate('https://admin.parago.example'), {
    error: null,
    allowed: true,
  });
  assert.deepEqual(await evaluate(undefined), {
    error: null,
    allowed: true,
  });
  const rejected = await evaluate('https://attacker.example');
  assert.equal(rejected.allowed, undefined);
  assert.equal(rejected.error.statusCode, 403);
});

test('production startup refuses missing or wildcard CORS origins', () => {
  const baseEnvironment = {
    ...process.env,
    NODE_ENV: 'production',
    DEPLOYMENT_ENV: 'production',
    MONGO_URI: 'mongodb://127.0.0.1:27017/parago-phase9-config',
    JWT_SECRET: 'phase9-production-access-secret',
    JWT_REFRESH_SECRET: 'phase9-production-refresh-secret',
    REDIS_URL: '',
    RUN_API_JOBS: 'true',
    RUN_WORKER_JOBS: 'false',
  };
  const load = (origin) => spawnSync(
    process.execPath,
    ['-e', "require('./src/config/env'); console.log('config-ok')"],
    {
      cwd: root,
      env: { ...baseEnvironment, CORS_ALLOWED_ORIGINS: origin },
      encoding: 'utf8',
    }
  );

  const missing = load('');
  assert.notEqual(missing.status, 0);
  assert.match(`${missing.stdout}${missing.stderr}`, /must not be empty/);
  const wildcard = load('*');
  assert.notEqual(wildcard.status, 0);
  assert.match(`${wildcard.stdout}${wildcard.stderr}`, /cannot contain a wildcard/);
  assert.equal(load('https://admin.parago.example').status, 0);
});

test('authenticated users behind one carrier IP receive independent limits',
    async () => {
  const limiter = createApiRateLimiters({ general: 2 }).general;
  const rateApp = express();
  rateApp.set('trust proxy', 1);
  rateApp.get('/resource', limiter, (_req, res) => res.json({ ok: true }));
  const firstToken = signToken({ sub: 'phase9-user-a' });
  const secondToken = signToken({ sub: 'phase9-user-b' });

  const call = (token) => request(rateApp)
    .get('/resource')
    .set('X-Forwarded-For', '100.64.1.10')
    .set('Authorization', `Bearer ${token}`);

  assert.equal((await call(firstToken)).status, 200);
  assert.equal((await call(firstToken)).status, 200);
  assert.equal((await call(firstToken)).status, 429);
  assert.equal((await call(secondToken)).status, 200);
  assert.equal((await call(secondToken)).status, 200);
});

test('structured HTTP logs exclude query values, authorization, and bodies',
    async () => {
  const lines = [];
  const logApp = express();
  logApp.use(requestContext);
  logApp.use(createStructuredHttpLogger({
    stream: { write: (line) => lines.push(line.trim()) },
  }));
  logApp.use(express.json());
  logApp.post('/passengers/me/location', (_req, res) => res.sendStatus(204));

  await request(logApp)
    .post('/passengers/me/location?token=query-secret&lat=14.6')
    .set('Authorization', 'Bearer header-secret')
    .send({ latitude: 14.6, longitude: 121.0 });

  assert.equal(lines.length, 1);
  const entry = JSON.parse(lines[0]);
  assert.equal(entry.path, '/passengers/me/location');
  assert.equal(typeof entry.requestId, 'string');
  assert.doesNotMatch(lines[0], /query-secret|header-secret|14\.6|121\.0/);
});

test('graceful shutdown is ordered and idempotent', async () => {
  const calls = [];
  const controller = createShutdownController({
    name: 'test-runtime',
    timeoutMs: 1000,
    stopAccepting: async () => calls.push('stop'),
    drain: async () => calls.push('drain'),
    closeDependencies: async () => calls.push('close'),
  });

  const first = controller.shutdown('SIGTERM');
  const second = controller.shutdown('SIGINT');
  assert.strictEqual(first, second);
  assert.deepEqual(await first, { signal: 'SIGTERM', timedOut: false });
  assert.deepEqual(calls, ['stop', 'drain', 'close']);
});

test('shutdown timeout is bounded', async () => {
  await assert.rejects(
    withTimeout(new Promise(() => {}), { name: 'blocked', timeoutMs: 20 }),
    /shutdown exceeded 20ms/
  );
});

test('Nginx and systemd templates enforce the deployment boundary', () => {
  const nginx = fs.readFileSync(
    path.join(root, 'deploy/nginx/parago.conf'),
    'utf8'
  );
  const apiUnit = fs.readFileSync(
    path.join(root, 'deploy/systemd/parago-api.service'),
    'utf8'
  );
  const workerUnit = fs.readFileSync(
    path.join(root, 'deploy/systemd/parago-worker.service'),
    'utf8'
  );

  assert.match(nginx, /proxy_set_header Upgrade \$http_upgrade/);
  assert.match(nginx, /proxy_set_header X-Forwarded-For \$remote_addr/);
  assert.match(nginx, /client_max_body_size 1m/);
  assert.match(apiUnit, /User=parago/);
  assert.match(apiUnit, /NoNewPrivileges=true/);
  assert.match(workerUnit, /RUN_WORKER_JOBS=true/);
});
