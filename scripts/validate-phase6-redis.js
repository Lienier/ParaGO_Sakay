const crypto = require('crypto');
const { createClient } = require('redis');

const redisUrl = String(process.env.REDIS_URL || '').trim();

if (!redisUrl.startsWith('rediss://')) {
  throw new Error('Phase 6 validation requires a TLS rediss:// connection');
}

const run = async () => {
  const client = createClient({
    url: redisUrl,
    socket: {
      connectTimeout: 5000,
      reconnectStrategy: false,
    },
  });

  client.on('error', () => {});

  const suffix = crypto.randomUUID();
  const stagingKey = `parago:staging:v1:validation:${suffix}`;
  const productionKey = `parago:production:v1:validation:${suffix}`;
  const lockKey = `parago:staging:v1:validation-lock:${suffix}`;
  const lockToken = crypto.randomUUID();
  const startedAt = Date.now();

  try {
    await client.connect();
    await client.set(stagingKey, 'staging', { EX: 60 });
    await client.set(productionKey, 'production', { EX: 60 });

    const [stagingValue, productionValue, stagingTtl, productionTtl] =
      await Promise.all([
        client.get(stagingKey),
        client.get(productionKey),
        client.ttl(stagingKey),
        client.ttl(productionKey),
      ]);

    if (stagingValue !== 'staging' || productionValue !== 'production') {
      throw new Error('Environment namespaces did not retain independent values');
    }
    if (stagingTtl < 1 || stagingTtl > 60 || productionTtl < 1 || productionTtl > 60) {
      throw new Error('Expected validation keys to have a bounded 60-second TTL');
    }

    const acquired = await client.set(lockKey, lockToken, { NX: true, PX: 5000 });
    const duplicateAcquire = await client.set(lockKey, 'other-owner', {
      NX: true,
      PX: 5000,
    });
    if (acquired !== 'OK' || duplicateAcquire !== null) {
      throw new Error('Distributed lock ownership validation failed');
    }

    console.log(
      JSON.stringify({
        tls: true,
        connected: true,
        namespacesIsolated: true,
        ttlSeconds: {
          staging: stagingTtl,
          production: productionTtl,
        },
        lockOwnership: true,
        durationMs: Date.now() - startedAt,
      })
    );
  } finally {
    if (client.isOpen) {
      await client.del([stagingKey, productionKey, lockKey]);
      await client.quit();
    }
  }
};

run().catch((error) => {
  console.error(
    JSON.stringify({
      tls: true,
      connected: false,
      error: error.message,
    })
  );
  process.exitCode = 1;
});
