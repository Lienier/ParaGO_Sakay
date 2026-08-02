const {
  workerFailedJobRetention,
  workerMaxBatchSize,
} = require('../config/env');
const {
  redisKey,
  executeRedis,
  redisGetJson,
  redisSetJson,
} = require('./redis.service');

const jobPayloadTtlSeconds = 180;
const processedJobTtlSeconds = 24 * 60 * 60;

const locationPendingKey = () => redisKey('queue', 'location', 'pending');
const automationPendingKey = () => redisKey('queue', 'automation', 'pending');
const retryQueueKey = () => redisKey('queue', 'retry');
const failedQueueKey = () => redisKey('queue', 'failed');
const latestLocationJobKey = (jeepneyId) =>
  redisKey('queue', 'location', 'latest', jeepneyId);
const latestAutomationJobKey = (tripId) =>
  redisKey('queue', 'automation', 'latest', tripId);
const processedJobKey = (idempotencyKey) =>
  redisKey('queue', 'processed', idempotencyKey);

const boundedBatchSize = (value) =>
  Math.max(1, Math.min(Number(value) || workerMaxBatchSize, workerMaxBatchSize));

const normalizePoppedMembers = (value) => {
  if (Array.isArray(value)) return value.map(String);
  return value == null ? [] : [String(value)];
};

const enqueueLatest = async ({ pendingKey, itemId, payloadKey, payload }) =>
  executeRedis(async (client) => {
    const transaction = client.multi();
    transaction.set(payloadKey, JSON.stringify(payload), {
      EX: jobPayloadTtlSeconds,
    });
    transaction.sAdd(pendingKey, String(itemId));
    await transaction.exec();
    return true;
  }, false);

const enqueueLocationWork = async (payload) => {
  const jeepneyId = String(payload?.jeepneyId || '').trim();
  if (!jeepneyId) return false;
  const queuedAt = payload.queuedAt || new Date().toISOString();
  return enqueueLatest({
    pendingKey: locationPendingKey(),
    itemId: jeepneyId,
    payloadKey: latestLocationJobKey(jeepneyId),
    payload: {
      ...payload,
      kind: 'location',
      jeepneyId,
      queuedAt,
      attempts: Number(payload.attempts || 0),
    },
  });
};

const enqueueAutomationWork = async (payload) => {
  const tripId = String(payload?.tripId || '').trim();
  if (!tripId) return false;
  const queuedAt = payload.queuedAt || new Date().toISOString();
  return enqueueLatest({
    pendingKey: automationPendingKey(),
    itemId: tripId,
    payloadKey: latestAutomationJobKey(tripId),
    payload: {
      ...payload,
      kind: 'automation',
      tripId,
      queuedAt,
      attempts: Number(payload.attempts || 0),
    },
  });
};

const drainLatest = async ({ pendingKey, payloadKeyFor, limit }) => {
  const members = await executeRedis(
    (client) => client.sPop(pendingKey, boundedBatchSize(limit)),
    null
  );
  if (members == null) return { available: false, jobs: [] };
  const ids = normalizePoppedMembers(members);
  const jobs = [];
  for (const id of ids) {
    const cached = await redisGetJson(payloadKeyFor(id));
    if (cached.value) jobs.push(cached.value);
  }
  return { available: true, jobs };
};

const drainLocationWork = async (limit = workerMaxBatchSize) =>
  drainLatest({
    pendingKey: locationPendingKey(),
    payloadKeyFor: latestLocationJobKey,
    limit,
  });

const drainAutomationWork = async (limit = workerMaxBatchSize) =>
  drainLatest({
    pendingKey: automationPendingKey(),
    payloadKeyFor: latestAutomationJobKey,
    limit,
  });

const scheduleRetry = async (job, delayMs) => {
  const retryAt = Date.now() + Math.max(100, Number(delayMs) || 100);
  const member = JSON.stringify({
    ...job,
    attempts: Number(job.attempts || 0) + 1,
    retryAt: new Date(retryAt).toISOString(),
  });
  return executeRedis(async (client) => {
    await client.zAdd(retryQueueKey(), [{ score: retryAt, value: member }]);
    return true;
  }, false);
};

const promoteDueRetries = async (limit = workerMaxBatchSize) =>
  executeRedis(async (client) => {
    const members = await client.zRangeByScore(
      retryQueueKey(),
      0,
      Date.now(),
      { LIMIT: { offset: 0, count: boundedBatchSize(limit) } }
    );
    if (!members.length) return 0;
    let promoted = 0;
    for (const member of members) {
      let job;
      try {
        job = JSON.parse(member);
      } catch (_error) {
        await client.zRem(retryQueueKey(), member);
        continue;
      }
      const queued =
        job.kind === 'location'
          ? await enqueueLocationWork(job)
          : job.kind === 'automation'
            ? await enqueueAutomationWork(job)
            : false;
      if (queued) {
        await client.zRem(retryQueueKey(), member);
        promoted += 1;
      }
    }
    return promoted;
  }, 0);

const recordFailedJob = async ({ job, error }) =>
  executeRedis(async (client) => {
    const entry = JSON.stringify({
      kind: String(job?.kind || 'unknown'),
      idempotencyKey: String(job?.idempotencyKey || ''),
      jeepneyId: job?.jeepneyId ? String(job.jeepneyId) : null,
      tripId: job?.tripId ? String(job.tripId) : null,
      attempts: Number(job?.attempts || 0),
      failedAt: new Date().toISOString(),
      error: String(error?.message || error || 'Unknown worker failure').slice(
        0,
        500
      ),
    });
    await client.lPush(failedQueueKey(), entry);
    await client.lTrim(
      failedQueueKey(),
      0,
      Math.max(1, workerFailedJobRetention) - 1
    );
    return true;
  }, false);

const listFailedJobs = async (limit = 50) =>
  executeRedis(async (client) => {
    const entries = await client.lRange(
      failedQueueKey(),
      0,
      Math.max(1, Math.min(Number(limit) || 50, 100)) - 1
    );
    return entries.flatMap((entry) => {
      try {
        return [JSON.parse(entry)];
      } catch (_error) {
        return [];
      }
    });
  }, []);

const getQueueHealth = async () =>
  executeRedis(async (client) => {
    const [locations, automation, retries, failed] = await Promise.all([
      client.sCard(locationPendingKey()),
      client.sCard(automationPendingKey()),
      client.zCard(retryQueueKey()),
      client.lLen(failedQueueKey()),
    ]);
    return {
      available: true,
      pendingLocations: locations,
      pendingAutomation: automation,
      scheduledRetries: retries,
      failedJobs: failed,
    };
  }, {
    available: false,
    pendingLocations: null,
    pendingAutomation: null,
    scheduledRetries: null,
    failedJobs: null,
  });

const isJobProcessed = async (idempotencyKey) => {
  const cached = await redisGetJson(processedJobKey(idempotencyKey));
  return cached.available && Boolean(cached.value);
};

const markJobProcessed = async (idempotencyKey) =>
  redisSetJson(
    processedJobKey(idempotencyKey),
    { processedAt: new Date().toISOString() },
    processedJobTtlSeconds
  );

module.exports = {
  locationPendingKey,
  automationPendingKey,
  retryQueueKey,
  failedQueueKey,
  latestLocationJobKey,
  latestAutomationJobKey,
  processedJobKey,
  enqueueLocationWork,
  enqueueAutomationWork,
  drainLocationWork,
  drainAutomationWork,
  scheduleRetry,
  promoteDueRetries,
  recordFailedJob,
  listFailedJobs,
  getQueueHealth,
  isJobProcessed,
  markJobProcessed,
};
