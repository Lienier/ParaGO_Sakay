const crypto = require('crypto');

const {
  namespace,
  initializeRedis,
  shutdownRedis,
  getRedisHealth,
  redisDelete,
} = require('../src/services/redis.service');
const {
  latestJeepLocationKey,
  driverActiveContextKey,
  etaCacheKey,
  cacheLatestJeepLocation,
  getLatestJeepLocation,
  getOrLoadDriverActiveContext,
  invalidateDriverActiveContext,
  coalesceEtaRequest,
} = require('../src/services/transientState.service');

const suffix = crypto.randomUUID();
const jeepneyId = `validation-jeep-${suffix}`;
const driverId = `validation-driver-${suffix}`;
const etaId = `validation-eta-${suffix}`;

const run = async () => {
  const connected = await initializeRedis();
  if (!connected || getRedisHealth().status !== 'healthy') {
    throw new Error('ParaGO Redis readiness did not become healthy');
  }

  let contextLoads = 0;
  let etaLoads = 0;

  try {
    await cacheLatestJeepLocation({
      jeepneyId,
      latitude: 14.5995,
      longitude: 120.9842,
      lastSeenAt: new Date(),
      streamId: suffix,
      sequence: 1,
    });
    const location = await getLatestJeepLocation(jeepneyId);
    if (!location.available || location.value?.sequence !== 1) {
      throw new Error('ParaGO latest-location cache validation failed');
    }

    const loadContext = async () => {
      contextLoads += 1;
      return { driverId, tripId: 'validation-trip' };
    };
    const firstContext = await getOrLoadDriverActiveContext({
      driverId,
      loader: loadContext,
    });
    const secondContext = await getOrLoadDriverActiveContext({
      driverId,
      loader: loadContext,
    });
    if (
      firstContext.source !== 'mongodb' ||
      secondContext.source !== 'redis' ||
      contextLoads !== 1
    ) {
      throw new Error('ParaGO active-context cache validation failed');
    }
    await invalidateDriverActiveContext(driverId);

    const etaLoader = async () => {
      etaLoads += 1;
      await new Promise((resolve) => setTimeout(resolve, 75));
      return { durationSeconds: 300 };
    };
    const etaResults = await Promise.all(
      Array.from({ length: 5 }, () =>
        coalesceEtaRequest({
          key: etaId,
          ttlSeconds: 25,
          loader: etaLoader,
          pollIntervalMs: 25,
        })
      )
    );
    if (
      etaLoads !== 1 ||
      etaResults.some((result) => result.durationSeconds !== 300)
    ) {
      throw new Error('ParaGO ETA coalescing validation failed');
    }

    console.log(
      JSON.stringify({
        connected: true,
        health: getRedisHealth().status,
        namespace,
        latestLocationCache: true,
        activeContextCache: true,
        activeContextInvalidation: true,
        etaRequests: etaResults.length,
        etaLoaderCalls: etaLoads,
      })
    );
  } finally {
    await redisDelete(
      latestJeepLocationKey(jeepneyId),
      driverActiveContextKey(driverId),
      etaCacheKey(etaId)
    );
    await shutdownRedis();
  }
};

run().catch((error) => {
  console.error(
    JSON.stringify({
      connected: false,
      error: error.message,
    })
  );
  process.exitCode = 1;
});
