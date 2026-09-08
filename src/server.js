const http = require('http');
const { pauseInactiveTrips } = require('./services/tripLifecycle.service');

const app = require('./app');
const connectDb = require('./config/db');
const { disconnectDb } = require('./config/db');
const {
  port,
  corsAllowedOrigins,
  runApiJobs,
  shutdownTimeoutMs,
} = require('./config/env');
const {
  attachSocketServer,
  closeSocketServer,
} = require('./realtime/socketServer');
const { checkAndReassignPassedRequests } = require('./services/pickupReassignment.service');
const {
  reconcileAnnouncementStatuses,
} = require('./services/announcement.service');
const {
  initializeRedis,
  getRedisHealth,
  shutdownRedis,
} = require('./services/redis.service');
const {
  createShutdownController,
  closeHttpServer,
} = require('./runtime/gracefulShutdown');

const start = async () => {
  await connectDb();
  await initializeRedis();
  console.log(`[Redis] status=${getRedisHealth().status}`);
  const server = http.createServer(app);
  attachSocketServer(server, { corsOrigins: corsAllowedOrigins });
  const intervals = [];

  if (runApiJobs) {
    // Compatibility mode keeps schedulers in the API until worker cutover.
    const reassignmentInterval = setInterval(() => {
      checkAndReassignPassedRequests().catch((error) => {
        console.error('[Background Job] Error in reassignment check:', error);
      });
    }, 15000);
    reassignmentInterval.unref?.();
    intervals.push(reassignmentInterval);

    const announcementInterval = setInterval(() => {
      reconcileAnnouncementStatuses().catch((error) => {
        console.error('[Background Job] Error reconciling announcements:', error);
      });
    }, 30000);
    announcementInterval.unref?.();
    intervals.push(announcementInterval);
    const inactivityInterval = setInterval(() => {
      pauseInactiveTrips().catch(() => console.error('[Trip lifecycle] Inactivity check failed'));
    }, 30000);
    inactivityInterval.unref?.();
    intervals.push(inactivityInterval);
    await reconcileAnnouncementStatuses();
  }

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, () => {
      server.off('error', reject);
      resolve();
    });
  });
  console.log(`ParaGO backend running on port ${port}`);
  console.log(
    runApiJobs
      ? 'Background jobs: compatibility API schedulers enabled'
      : 'Background jobs: delegated to worker process'
  );

  const shutdownController = createShutdownController({
    name: 'ParaGO API',
    timeoutMs: shutdownTimeoutMs,
    log: (message) => console.log(message),
    stopAccepting: async () => {
      for (const interval of intervals) clearInterval(interval);
      const closingHttp = closeHttpServer(server);
      await closeSocketServer();
      await closingHttp;
    },
    closeDependencies: async () => {
      await shutdownRedis();
      await disconnectDb();
    },
  });

  const handleSignal = (signal) => {
    void shutdownController.shutdown(signal).then(
      () => process.exit(0),
      (error) => {
        console.error('API shutdown failed:', error.message);
        process.exit(1);
      }
    );
  };
  process.once('SIGTERM', () => handleSignal('SIGTERM'));
  process.once('SIGINT', () => handleSignal('SIGINT'));

  return { server, shutdownController };
};

if (require.main === module) {
  start().catch((error) => {
    console.error('Unable to start app:', error.message);
    process.exit(1);
  });
}

module.exports = { start };
