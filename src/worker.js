const connectDb = require('./config/db');
const { disconnectDb } = require('./config/db');
const { runWorkerJobs, shutdownTimeoutMs } = require('./config/env');
const {
  initializeRedis,
  getRedisHealth,
  shutdownRedis,
} = require('./services/redis.service');
const { AsyncWorker } = require('./workers/asyncWorker');
const {
  createShutdownController,
} = require('./runtime/gracefulShutdown');

const start = async () => {
  if (!runWorkerJobs) {
    throw new Error('Worker process requires RUN_WORKER_JOBS=true');
  }
  await connectDb();
  const redisReady = await initializeRedis();
  if (!redisReady) {
    throw new Error('Worker process requires a healthy Redis connection');
  }
  console.log(`[Worker] Redis status=${getRedisHealth().status}`);
  const worker = new AsyncWorker();
  worker.start();
  console.log('ParaGO asynchronous worker started');

  const shutdownController = createShutdownController({
    name: 'ParaGO worker',
    timeoutMs: shutdownTimeoutMs,
    log: (message) => console.log(message),
    stopAccepting: async () => worker.stop(),
    drain: async () => worker.drain({
      timeoutMs: Math.max(1000, shutdownTimeoutMs - 2000),
    }),
    closeDependencies: async () => {
      await shutdownRedis();
      await disconnectDb();
    },
  });
  const handleSignal = (signal) => {
    void shutdownController.shutdown(signal).then(
      () => process.exit(0),
      (error) => {
        console.error('Worker shutdown failed:', error.message);
        process.exit(1);
      }
    );
  };
  process.once('SIGTERM', () => handleSignal('SIGTERM'));
  process.once('SIGINT', () => handleSignal('SIGINT'));
  return { worker, shutdownController };
};

if (require.main === module) {
  start().catch((error) => {
    console.error('Unable to start worker:', error.message);
    process.exit(1);
  });
}

module.exports = { start };
