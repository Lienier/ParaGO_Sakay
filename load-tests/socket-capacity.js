const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');
const { io } = require('socket.io-client');

const {
  loadManifestPath,
  positiveInteger,
  rootDir,
  validateStagingBaseUrl,
} = require('../scripts/phase10-safety');

const parseArguments = (args) => {
  const values = {};
  for (const argument of args) {
    if (!argument.startsWith('--') || !argument.includes('=')) continue;
    const separator = argument.indexOf('=');
    values[argument.slice(2, separator)] = argument.slice(separator + 1);
  }
  return values;
};

const percentile = (values, percentage) => {
  if (!values.length) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.min(
    sorted.length - 1,
    Math.ceil((percentage / 100) * sorted.length) - 1
  );
  return Number(sorted[Math.max(index, 0)].toFixed(2));
};

const summarize = ({ samples, counters, startedAt, endedAt, settings }) => ({
  schemaVersion: 1,
  profile: `${settings.passengers}p`,
  startedAt,
  endedAt,
  durationSeconds: Math.round((Date.parse(endedAt) - Date.parse(startedAt)) / 1000),
  settings,
  metrics: {
    routeBatchDeliveryMs: {
      count: samples.delivery.length,
      p50: percentile(samples.delivery, 50),
      p95: percentile(samples.delivery, 95),
      max: samples.delivery.length ? Math.max(...samples.delivery) : null,
    },
    connectionMs: {
      count: samples.connection.length,
      p95: percentile(samples.connection, 95),
    },
    subscriptionMs: {
      count: samples.subscription.length,
      p95: percentile(samples.subscription, 95),
    },
    ...counters,
  },
  acceptance: {
    routeBatchP95Below1500Ms:
      samples.delivery.length > 0 && percentile(samples.delivery, 95) < 1500,
    unauthorizedDeliveriesZero: counters.unauthorizedDeliveries === 0,
    sequenceRegressionsZero: counters.sequenceRegressions === 0,
    subscriptionFailuresZero: counters.subscriptionFailures === 0,
  },
});

async function run() {
  const args = parseArguments(process.argv.slice(2));
  if (args['dry-run'] === 'true') {
    console.log('Phase 10 Socket.IO harness configuration is valid.');
    return;
  }
  const baseUrl = validateStagingBaseUrl(args.url || process.env.BASE_URL);
  const passengerCount = positiveInteger(
    args.passengers || process.env.PASSENGERS || 20,
    'passengers',
    1000
  );
  const durationSeconds = positiveInteger(
    args.duration || process.env.DURATION_SECONDS || 300,
    'duration',
    10800
  );
  const reconnectPercent = Math.min(
    100,
    positiveInteger(args.reconnect || 10, 'reconnect', 100)
  );
  const manifest = JSON.parse(fs.readFileSync(loadManifestPath, 'utf8'));
  if (
    manifest.environment !== 'staging' ||
    manifest.database !== 'parago_staging' ||
    passengerCount > manifest.passengers.length
  ) {
    throw new Error('Synthetic staging manifest is invalid or too small');
  }

  const startedAt = new Date().toISOString();
  const sockets = [];
  const samples = { delivery: [], connection: [], subscription: [] };
  const counters = {
    connected: 0,
    subscriptionFailures: 0,
    batches: 0,
    vehicleUpdates: 0,
    sequenceRegressions: 0,
    unauthorizedDeliveries: 0,
    disconnects: 0,
    reconnects: 0,
  };

  await Promise.all(
    manifest.passengers.slice(0, passengerCount).map((account, index) =>
      new Promise((resolve, reject) => {
        const connectionStarted = performance.now();
        const socket = io(baseUrl, {
          auth: { token: account.token },
          transports: ['websocket'],
          reconnection: true,
          timeout: 15000,
        });
        sockets.push(socket);
        let lastSequence = -1;
        let ready = false;
        const timeout = setTimeout(() => {
          if (!ready) reject(new Error(`Socket ${index} timed out`));
        }, 20000);

        socket.on('connect', () => {
          counters.connected += 1;
          samples.connection.push(performance.now() - connectionStarted);
        });
        socket.on('socket.ready', () => {
          const subscriptionStarted = performance.now();
          socket.emit('subscribe.route', manifest.routeId, (ack) => {
            samples.subscription.push(performance.now() - subscriptionStarted);
            if (!ack?.ok) counters.subscriptionFailures += 1;
            if (!ready) {
              ready = true;
              clearTimeout(timeout);
              resolve();
            }
          });
        });
        socket.on('route.vehicles.updated', (payload) => {
          if (String(payload?.routeId) !== String(manifest.routeId)) {
            counters.unauthorizedDeliveries += 1;
            return;
          }
          const sequence = Number(payload.sequence);
          if (!payload.snapshot && sequence <= lastSequence) {
            counters.sequenceRegressions += 1;
          }
          if (!payload.snapshot) lastSequence = sequence;
          const generatedAt = Date.parse(payload.generatedAt);
          if (Number.isFinite(generatedAt)) {
            samples.delivery.push(Math.max(0, Date.now() - generatedAt));
          }
          counters.batches += 1;
          counters.vehicleUpdates += Array.isArray(payload.vehicles)
            ? payload.vehicles.length
            : 0;
        });
        socket.on('disconnect', () => {
          counters.disconnects += 1;
        });
        socket.io.on('reconnect', () => {
          counters.reconnects += 1;
        });
        socket.on('connect_error', (error) => {
          if (!ready) {
            clearTimeout(timeout);
            reject(error);
          }
        });
      })
    )
  );

  const reconnectCount = Math.floor((passengerCount * reconnectPercent) / 100);
  setTimeout(() => {
    for (const socket of sockets.slice(0, reconnectCount)) {
      socket.io.engine?.close();
    }
  }, Math.min(30000, Math.floor((durationSeconds * 1000) / 3))).unref();

  await new Promise((resolve) => setTimeout(resolve, durationSeconds * 1000));
  for (const socket of sockets) socket.close();
  const endedAt = new Date().toISOString();
  const result = summarize({
    samples,
    counters,
    startedAt,
    endedAt,
    settings: {
      passengers: passengerCount,
      durationSeconds,
      reconnectPercent,
      baseUrl,
    },
  });
  const outputDirectory = path.join(rootDir, 'artifacts', 'phase10');
  fs.mkdirSync(outputDirectory, { recursive: true });
  const outputPath = path.join(
    outputDirectory,
    `${passengerCount}p-socket-summary.json`
  );
  fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`);
  console.log(`Socket.IO summary written to ${outputPath}`);
  if (Object.values(result.acceptance).some((value) => value !== true)) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  run().catch((error) => {
    console.error(`Phase 10 Socket.IO harness failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = { parseArguments, percentile, summarize };
