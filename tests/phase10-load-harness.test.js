const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  positiveInteger,
  validateStagingBaseUrl,
} = require('../scripts/phase10-safety');
const {
  buildPlan,
  maximumDriverCount,
  maximumPassengerCount,
} = require('../scripts/prepare-phase10-load-data');
const {
  parseArguments,
  percentile,
  summarize,
} = require('../load-tests/socket-capacity');
const {
  appName,
  branch,
  buildSpec,
  bootstrapApiCommand,
  bootstrapWorkerCommand,
  valkeyClusterName,
} = require('../scripts/build-phase10-digitalocean-spec');
const { compileResults } = require('../scripts/summarize-phase10-results');
const {
  parseArguments: parseProfileArguments,
  partitionTripIds,
  syntheticTripNote,
} = require('../scripts/configure-phase10-profile');

const rootDir = path.resolve(__dirname, '..');

test('Phase 10 URL guard permits staging and localhost but rejects production', () => {
  assert.equal(
    validateStagingBaseUrl('https://parago-capacity-staging.example/path'),
    'https://parago-capacity-staging.example'
  );
  assert.equal(validateStagingBaseUrl('http://127.0.0.1:5001'), 'http://127.0.0.1:5001');
  assert.equal(validateStagingBaseUrl('http://localhost:5001'), 'http://localhost:5001');
  assert.throws(
    () =>
      validateStagingBaseUrl(
        'https://paragosakay-app-qulmw.ondigitalocean.app'
      ),
    /known production/
  );
  assert.throws(
    () => validateStagingBaseUrl('https://unmarked.example'),
    /must contain staging/
  );
});

test('Phase 10 fixture counts are bounded and generated identities are unique', () => {
  assert.equal(positiveInteger('50', 'drivers', 200), 50);
  assert.throws(() => positiveInteger('201', 'drivers', 200), /1 to 200/);
  const plan = buildPlan({
    driverCount: maximumDriverCount,
    passengerCount: maximumPassengerCount,
    now: new Date(),
  });
  const emails = [
    ...plan.drivers.map((entry) => entry.email),
    ...plan.passengers.map((entry) => entry.email),
  ];
  assert.equal(new Set(emails).size, emails.length);
});

test('Socket harness parses arguments and computes deterministic percentiles', () => {
  assert.deepEqual(parseArguments(['--passengers=200', '--duration=7200']), {
    passengers: '200',
    duration: '7200',
  });
  assert.equal(percentile([10, 20, 30, 40, 50], 95), 50);
  assert.equal(percentile([], 95), null);
});

test('Socket summary fails acceptance on leakage, regressions, or slow batches', () => {
  const result = summarize({
    samples: {
      delivery: [100, 200, 1600],
      connection: [10],
      subscription: [15],
    },
    counters: {
      connected: 1,
      subscriptionFailures: 0,
      batches: 3,
      vehicleUpdates: 3,
      sequenceRegressions: 1,
      unauthorizedDeliveries: 1,
      disconnects: 0,
      reconnects: 0,
    },
    startedAt: '2026-08-02T00:00:00.000Z',
    endedAt: '2026-08-02T00:01:00.000Z',
    settings: { passengers: 1, durationSeconds: 60, reconnectPercent: 10 },
  });
  assert.equal(result.acceptance.routeBatchP95Below1500Ms, false);
  assert.equal(result.acceptance.unauthorizedDeliveriesZero, false);
  assert.equal(result.acceptance.sequenceRegressionsZero, false);
});

test('k6 workload has production and live Google safety interlocks', () => {
  const source = fs.readFileSync(
    path.join(rootDir, 'load-tests', 'k6', 'rest-capacity.js'),
    'utf8'
  );
  assert.match(source, /BASE_URL must identify the isolated staging service/);
  assert.match(source, /GOOGLE_BUDGET_APPROVED/);
  assert.match(source, /p\(95\)<250/);
  assert.match(source, /p\(95\)<500/);
  assert.match(source, /rate<0\.01/);
  assert.match(source, /randomUuidV4\(\)/);
  assert.doesNotMatch(source, /streamId: `phase10-/);
  assert.match(source, /trips\/active\?routeId=\$\{manifest\.routeId\}/);
});

test('Phase 10 profile configuration activates only the requested trip prefix', () => {
  assert.deepEqual(parseProfileArguments(['--drivers=5']), { drivers: '5' });
  const drivers = Array.from({ length: 8 }, (_, index) => ({
    tripId: `trip-${index + 1}`,
  }));
  assert.deepEqual(partitionTripIds(drivers, 3), {
    activeTripIds: ['trip-1', 'trip-2', 'trip-3'],
    inactiveTripIds: ['trip-4', 'trip-5', 'trip-6', 'trip-7', 'trip-8'],
  });
  assert.equal(syntheticTripNote, 'Phase 10 synthetic capacity trip.');
});

test('DigitalOcean staging spec isolates data, jobs, source branch, and namespace', () => {
  const staging = {
    STAGING_MONGO_URI:
      'mongodb+srv://synthetic:secret@staging.example/parago_staging',
    STAGING_JWT_SECRET: 'a'.repeat(64),
    STAGING_JWT_REFRESH_SECRET: 'b'.repeat(64),
  };
  const spec = buildSpec({ staging });
  assert.equal(spec.name, appName);
  assert.equal(spec.services[0].github.branch, branch);
  assert.equal(spec.services[0].github.deploy_on_push, false);
  assert.equal(spec.workers[0].github.branch, branch);
  assert.equal(spec.databases[0].cluster_name, valkeyClusterName);
  const environment = Object.fromEntries(
    spec.envs.map((entry) => [entry.key, entry.value])
  );
  assert.match(environment.MONGO_URI, /parago_staging/);
  assert.equal(environment.REDIS_URL, '${phase10-valkey.DATABASE_URL}');
  assert.equal(environment.REDIS_NAMESPACE, 'parago:staging:phase10:v1');
  assert.equal(environment.ASYNC_LOCATION_PROCESSING_ENABLED, 'true');
  assert.equal(environment.GOOGLE_ROUTES_API_KEY, '');
  assert.deepEqual(
    spec.services[0].alerts.map((alert) => alert.rule),
    ['CPU_UTILIZATION', 'MEM_UTILIZATION']
  );
  assert.deepEqual(
    spec.workers[0].alerts.map((alert) => alert.rule),
    ['CPU_UTILIZATION', 'MEM_UTILIZATION']
  );
  assert.deepEqual(spec.alerts.map((alert) => alert.rule), [
    'DEPLOYMENT_FAILED',
  ]);
  assert.deepEqual(spec.egress, { type: 'DEDICATED_IP' });
  assert.equal(spec.vpc, undefined);
  assert.equal(
    spec.services[0].envs.find((entry) => entry.key === 'RUN_WORKER_JOBS').value,
    'false'
  );
  assert.equal(
    spec.workers[0].envs.find((entry) => entry.key === 'RUN_WORKER_JOBS').value,
    'true'
  );

  const bootstrap = buildSpec({ staging, bootstrapEgress: true });
  assert.equal(bootstrap.services[0].run_command, bootstrapApiCommand);
  assert.match(bootstrapApiCommand, /api\.ipify\.org/);
  assert.doesNotMatch(bootstrapApiCommand, /MONGO|REDIS|JWT/);
  assert.equal(bootstrap.workers[0].run_command, bootstrapWorkerCommand);
  assert.deepEqual(bootstrap.egress, { type: 'DEDICATED_IP' });
  assert.equal(bootstrap.vpc, undefined);
});

test('capacity report does not pass without every measured acceptance check', () => {
  const compiled = compileResults([
    {
      file: '50d-200p-rest-summary.json',
      value: {
        metrics: {
          parago_location_latency: { values: { 'p(95)': 200 } },
          parago_ordinary_latency: { values: { 'p(95)': 400 } },
          parago_request_errors: { values: { rate: 0.02 } },
        },
      },
    },
  ]);
  assert.equal(compiled.passed, false);
  assert.equal(
    compiled.results[0].acceptance.errorRateBelowOnePercent,
    false
  );
});
