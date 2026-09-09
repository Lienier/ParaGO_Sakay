const { pauseInactiveTrips } = require('../services/tripLifecycle.service');
const Jeepney = require('../models/jeepney');
const {
  workerAutomationPollIntervalMs,
  workerLocationFlushIntervalMs,
  workerMaxAttempts,
  workerMaxBatchSize,
} = require('../config/env');
const {
  buildPersistentLocationOrderFilter,
  persistentLocationOrderUpdate,
} = require('../services/driverLocationOrdering.service');
const {
  processDestinationApproachAlerts,
} = require('../services/destinationApproach.service');
const {
  processAutomaticBoardingForTrip,
} = require('../services/automaticBoarding.service');
const {
  processAutomaticOffboardingForTrip,
} = require('../services/automaticOffboarding.service');
const {
  checkAndReassignPassedRequests,
} = require('../services/pickupReassignment.service');
const {
  reconcileAnnouncementStatuses,
} = require('../services/announcement.service');
const {
  acquireRedisLock,
  releaseRedisLock,
  redisKey,
} = require('../services/redis.service');
const {
  drainLocationWork,
  drainAutomationWork,
  scheduleRetry,
  promoteDueRetries,
  recordFailedJob,
  isJobProcessed,
  markJobProcessed,
  getQueueHealth,
} = require('../services/asyncJobQueue.service');

const retryDelayMs = (attempts) =>
  Math.min(250 * 2 ** Math.max(0, Number(attempts || 0)), 5000);

const validDate = (value, fallback = new Date()) => {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
};

const locationOperation = (job) => {
  const serverReceivedAt = validDate(job.serverReceivedAt);
  const ordered = Boolean(job.streamId && job.sequence && job.capturedAt);
  const filter = ordered
    ? buildPersistentLocationOrderFilter({
        jeepneyId: job.jeepneyId,
        streamId: job.streamId,
        sequence: Number(job.sequence),
        capturedAt: validDate(job.capturedAt),
      })
    : { _id: job.jeepneyId };
  const update = {
    lastKnownLocation: {
      type: 'Point',
      coordinates: [Number(job.longitude), Number(job.latitude)],
    },
    lastSeenAt: serverReceivedAt,
  };
  if (ordered) {
    update.latestLocationOrder = persistentLocationOrderUpdate({
      streamId: job.streamId,
      sequence: Number(job.sequence),
      capturedAt: validDate(job.capturedAt),
      serverReceivedAt,
    });
  }
  return {
    updateOne: {
      filter,
      update: { $set: update },
    },
  };
};

class AsyncWorker {
  constructor({
    now = () => new Date(),
    locationFlushIntervalMs = workerLocationFlushIntervalMs,
    automationPollIntervalMs = workerAutomationPollIntervalMs,
    maxBatchSize = workerMaxBatchSize,
    maxAttempts = workerMaxAttempts,
    dependencies = {},
  } = {}) {
    this.now = now;
    this.locationFlushIntervalMs = Math.max(
      100,
      Number(locationFlushIntervalMs) || 5000
    );
    this.automationPollIntervalMs = Math.max(
      100,
      Number(automationPollIntervalMs) || 1000
    );
    this.maxBatchSize = Math.max(1, Number(maxBatchSize) || 500);
    this.maxAttempts = Math.max(1, Number(maxAttempts) || 5);
    this.dependencies = {
      jeepneyModel: Jeepney,
      processDestinationApproachAlerts,
      processAutomaticBoardingForTrip,
      processAutomaticOffboardingForTrip,
      checkAndReassignPassedRequests,
      reconcileAnnouncementStatuses,
      pauseInactiveTrips,
      acquireRedisLock,
      releaseRedisLock,
      drainLocationWork,
      drainAutomationWork,
      scheduleRetry,
      promoteDueRetries,
      recordFailedJob,
      isJobProcessed,
      markJobProcessed,
      getQueueHealth,
      ...dependencies,
    };
    this.timers = [];
    this.locationRunning = false;
    this.automationRunning = false;
    this.schedulerRunning = false;
    this.lastAnnouncementReconcileAtMs = 0;
    this.metrics = {
      lastLocationFlushAt: null,
      lastAutomationRunAt: null,
      lastQueueLagMs: 0,
      maxQueueLagMs: 0,
      persistedLocations: 0,
      processedAutomation: 0,
      retriedJobs: 0,
      failedJobs: 0,
    };
  }

  async handleFailure(job, error) {
    const attempts = Number(job.attempts || 0) + 1;
    if (attempts >= this.maxAttempts) {
      await this.dependencies.recordFailedJob({
        job: { ...job, attempts },
        error,
      });
      this.metrics.failedJobs += 1;
      return;
    }
    await this.dependencies.scheduleRetry(job, retryDelayMs(attempts));
    this.metrics.retriedJobs += 1;
  }

  recordLag(job) {
    const queuedAt = Date.parse(job?.queuedAt || '');
    if (!Number.isFinite(queuedAt)) return;
    const lag = Math.max(0, this.now().getTime() - queuedAt);
    this.metrics.lastQueueLagMs = lag;
    this.metrics.maxQueueLagMs = Math.max(this.metrics.maxQueueLagMs, lag);
  }

  async flushLocations() {
    if (this.locationRunning) return { skipped: true, persisted: 0 };
    this.locationRunning = true;
    try {
      await this.dependencies.promoteDueRetries(this.maxBatchSize);
      const drained = await this.dependencies.drainLocationWork(
        this.maxBatchSize
      );
      if (!drained.available || drained.jobs.length === 0) {
        return { skipped: false, persisted: 0 };
      }
      const validJobs = drained.jobs.filter(
        (job) =>
          job?.jeepneyId &&
          Number.isFinite(Number(job.latitude)) &&
          Number.isFinite(Number(job.longitude)) &&
          Number(job.latitude) >= -90 &&
          Number(job.latitude) <= 90 &&
          Number(job.longitude) >= -180 &&
          Number(job.longitude) <= 180
      );
      try {
        if (validJobs.length) {
          await this.dependencies.jeepneyModel.bulkWrite(
            validJobs.map(locationOperation),
            {
              ordered: false,
            }
          );
        }
        for (const job of validJobs) this.recordLag(job);
        this.metrics.persistedLocations += validJobs.length;
        this.metrics.lastLocationFlushAt = this.now().toISOString();
        return { skipped: false, persisted: validJobs.length };
      } catch (error) {
        await Promise.all(
          validJobs.map((job) => this.handleFailure(job, error))
        );
        return { skipped: false, persisted: 0, failed: validJobs.length };
      }
    } finally {
      this.locationRunning = false;
    }
  }

  async processAutomationJob(job) {
    const idempotencyKey = String(
      job.idempotencyKey ||
        `${job.tripId}:${job.streamId || 'legacy'}:${job.sequence || 'latest'}`
    );
    if (await this.dependencies.isJobProcessed(idempotencyKey)) return false;
    const lockKey = redisKey('lock', 'automation', 'trip', job.tripId);
    const token = await this.dependencies.acquireRedisLock(lockKey, 15000);
    if (!token) return false;
    try {
      if (await this.dependencies.isJobProcessed(idempotencyKey)) return false;
      const now = this.now();
      const capturedAt = validDate(job.capturedAt || job.serverReceivedAt);
      const age = capturedAt ? now - capturedAt : Infinity;
      if (age < 0 || age > 15000) {
        await this.dependencies.markJobProcessed(idempotencyKey);
        this.recordLag(job);
        return true;
      }
      const jeepneyLocation = {
        lastKnownLocation: {type: 'Point', coordinates: [Number(job.longitude), Number(job.latitude)]},
        lastSeenAt: capturedAt,
      };
      await this.dependencies.processDestinationApproachAlerts({
        tripSessionId: job.tripId,
        driverUserId: job.driverUserId,
        latitude: Number(job.latitude),
        longitude: Number(job.longitude),
        previousLatitude:
          job.previousLatitude == null ? null : Number(job.previousLatitude),
        previousLongitude:
          job.previousLongitude == null ? null : Number(job.previousLongitude),
      });
      await this.dependencies.processAutomaticBoardingForTrip({
        tripSessionId: job.tripId,
        jeepneyLocation,
        now,
      });
      await this.dependencies.processAutomaticOffboardingForTrip({
        tripSessionId: job.tripId,
        jeepneyLocation,
        now,
      });
      await this.dependencies.markJobProcessed(idempotencyKey);
      this.recordLag(job);
      this.metrics.processedAutomation += 1;
      this.metrics.lastAutomationRunAt = this.now().toISOString();
      return true;
    } finally {
      await this.dependencies.releaseRedisLock(lockKey, token);
    }
  }

  async processAutomation() {
    if (this.automationRunning) return { skipped: true, processed: 0 };
    this.automationRunning = true;
    try {
      await this.dependencies.promoteDueRetries(this.maxBatchSize);
      const drained = await this.dependencies.drainAutomationWork(
        this.maxBatchSize
      );
      if (!drained.available) return { skipped: false, processed: 0 };
      let processed = 0;
      for (const job of drained.jobs) {
        try {
          if (await this.processAutomationJob(job)) processed += 1;
        } catch (error) {
          await this.handleFailure(job, error);
        }
      }
      return { skipped: false, processed };
    } finally {
      this.automationRunning = false;
    }
  }

  async runScheduledJobs() {
    if (this.schedulerRunning) return { skipped: true };
    this.schedulerRunning = true;
    const lockKey = redisKey('lock', 'worker', 'scheduled');
    const token = await this.dependencies.acquireRedisLock(lockKey, 25000);
    if (!token) {
      this.schedulerRunning = false;
      return { skipped: true };
    }
    try {
      await this.dependencies.checkAndReassignPassedRequests();
      let announcements = null;
      const nowMs = this.now().getTime();
      if (nowMs - this.lastAnnouncementReconcileAtMs >= 30000) {
        announcements =
          await this.dependencies.reconcileAnnouncementStatuses();
        await this.dependencies.pauseInactiveTrips();
        this.lastAnnouncementReconcileAtMs = nowMs;
      }
      return { skipped: false, announcements };
    } finally {
      await this.dependencies.releaseRedisLock(lockKey, token);
      this.schedulerRunning = false;
    }
  }

  start() {
    if (this.timers.length) return;
    const locationTimer = setInterval(
      () => void this.flushLocations(),
      this.locationFlushIntervalMs
    );
    const automationTimer = setInterval(
      () => void this.processAutomation(),
      this.automationPollIntervalMs
    );
    const schedulerTimer = setInterval(
      () => void this.runScheduledJobs(),
      15000
    );
    for (const timer of [locationTimer, automationTimer, schedulerTimer]) {
      timer.unref?.();
      this.timers.push(timer);
    }
    void this.flushLocations();
    void this.processAutomation();
    void this.runScheduledJobs();
  }

  stop() {
    for (const timer of this.timers) clearInterval(timer);
    this.timers = [];
  }

  async drain({ timeoutMs = 10000, pollIntervalMs = 25 } = {}) {
    this.stop();
    const deadline = Date.now() + Math.max(100, Number(timeoutMs) || 10000);
    while (
      this.locationRunning ||
      this.automationRunning ||
      this.schedulerRunning
    ) {
      if (Date.now() >= deadline) {
        throw new Error('Worker drain timed out while jobs were active');
      }
      await new Promise((resolve) =>
        setTimeout(resolve, Math.max(5, Number(pollIntervalMs) || 25))
      );
    }
    return this.flushLocations();
  }

  async health() {
    return {
      ...this.metrics,
      queues: await this.dependencies.getQueueHealth(),
    };
  }
}

module.exports = {
  AsyncWorker,
  locationOperation,
  retryDelayMs,
};
