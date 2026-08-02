const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const baseEnvironment = {
  ...process.env,
  MONGO_URI: 'mongodb://127.0.0.1:27017/parago-worker-controls',
  JWT_SECRET: 'phase7-worker-control-secret',
  NODE_ENV: 'test',
  DEPLOYMENT_ENV: 'test',
};

const loadConfig = (overrides) =>
  spawnSync(
    process.execPath,
    ['-e', "require('./src/config/env'); console.log('config-ok')"],
    {
      cwd: root,
      env: { ...baseEnvironment, ...overrides },
      encoding: 'utf8',
    }
  );

test('API and worker schedulers cannot both be enabled', () => {
  const result = loadConfig({
    RUN_API_JOBS: 'true',
    RUN_WORKER_JOBS: 'true',
  });
  assert.notEqual(result.status, 0);
  assert.match(
    `${result.stdout}${result.stderr}`,
    /RUN_API_JOBS and RUN_WORKER_JOBS cannot both be enabled/
  );
});

test('worker-only process controls are accepted', () => {
  const result = loadConfig({
    RUN_API_JOBS: 'false',
    RUN_WORKER_JOBS: 'true',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /config-ok/);
});

test('asynchronous location mode refuses startup without Redis', () => {
  const result = loadConfig({
    RUN_API_JOBS: 'false',
    RUN_WORKER_JOBS: 'false',
    ASYNC_LOCATION_PROCESSING_ENABLED: 'true',
    REDIS_URL: '',
  });
  assert.notEqual(result.status, 0);
  assert.match(
    `${result.stdout}${result.stderr}`,
    /ASYNC_LOCATION_PROCESSING_ENABLED requires REDIS_URL/
  );
});
