const crypto = require('crypto');
const { createClient } = require('redis');
const {
  redisUrl,
  redisNamespace,
  redisConnectTimeoutMs,
  deploymentEnvironment,
} = require('../config/env');

const namespacePattern = /^[a-z0-9][a-z0-9:_-]{2,80}$/i;

let client = null;
let injectedClient = false;
const subscribers = new Set();
let state = {
  configured: Boolean(redisUrl),
  ready: false,
  lastErrorAt: null,
};

const validateNamespace = (value) => {
  const normalized = String(value || '').trim();
  if (!namespacePattern.test(normalized)) {
    throw new Error('REDIS_NAMESPACE contains unsupported characters');
  }
  return normalized;
};

const namespace = validateNamespace(redisNamespace);
if (
  redisUrl &&
  !namespace.toLowerCase().includes(`:${deploymentEnvironment.toLowerCase()}:`)
) {
  throw new Error('REDIS_NAMESPACE must include DEPLOYMENT_ENV');
}

const markFailure = () => {
  state.ready = false;
  state.lastErrorAt = new Date().toISOString();
};

const redisKey = (...parts) => {
  const normalized = parts.map((part) =>
    encodeURIComponent(String(part ?? '').trim())
  );
  if (normalized.some((part) => !part)) {
    throw new Error('Redis key parts must be non-empty');
  }
  return [namespace, ...normalized].join(':');
};

const initializeRedis = async () => {
  if (client?.isReady) {
    state.ready = true;
    return true;
  }
  if (!redisUrl || injectedClient) {
    state.configured = Boolean(client);
    state.ready = Boolean(client?.isReady);
    return state.ready;
  }

  client = createClient({
    url: redisUrl,
    // Keep the wire protocol explicit so local Redis 5 and managed Redis/Valkey
    // deployments share the same command behavior. The counters and cache
    // operations used by ParaGO do not require RESP3-only features.
    RESP: 2,
    socket: {
      connectTimeout: redisConnectTimeoutMs,
      reconnectStrategy: (retries) => Math.min(250 * 2 ** retries, 5000),
    },
  });
  client.on('error', markFailure);
  client.on('ready', () => {
    state.ready = true;
    state.lastErrorAt = null;
  });
  client.on('end', () => {
    state.ready = false;
  });

  try {
    const connection = client.connect().catch(() => {
      markFailure();
      return false;
    });
    const connected = await Promise.race([
      connection,
      new Promise((resolve) =>
        setTimeout(() => resolve(false), redisConnectTimeoutMs + 250)
      ),
    ]);
    state.configured = true;
    state.ready = connected !== false && Boolean(client.isReady);
    return state.ready;
  } catch (_error) {
    markFailure();
    return false;
  }
};

const shutdownRedis = async () => {
  for (const subscriber of subscribers) {
    try {
      if (subscriber.isOpen) await subscriber.close();
    } catch (_error) {
      // Continue closing the remaining Redis connections.
    }
  }
  subscribers.clear();
  if (!client || injectedClient) return;
  try {
    if (client.isOpen) {
      await client.close();
    }
  } finally {
    client = null;
    state.ready = false;
  }
};

const getRedisHealth = () => ({
  configured: state.configured,
  ready: Boolean(client?.isReady && state.ready),
  status: !state.configured
    ? 'disabled'
    : client?.isReady && state.ready
      ? 'healthy'
      : 'unhealthy',
});

const execute = async (operation, fallback) => {
  if (!client?.isReady) return fallback;
  try {
    const result = await operation(client);
    state.ready = true;
    state.lastErrorAt = null;
    return result;
  } catch (_error) {
    markFailure();
    return fallback;
  }
};

const executeRedis = async (operation, fallback = null) => {
  if (typeof operation !== 'function') {
    throw new TypeError('Redis operation must be a function');
  }
  return execute(operation, fallback);
};

const publishRedisEvent = async (channel, payload) =>
  executeRedis(async (activeClient) => {
    await activeClient.publish(channel, JSON.stringify(payload));
    return true;
  }, false);

const subscribeRedisChannel = async (channel, onMessage) => {
  if (!client?.isReady || injectedClient || typeof onMessage !== 'function') {
    return null;
  }
  const subscriber = client.duplicate();
  subscriber.on('error', markFailure);
  try {
    await subscriber.connect();
    await subscriber.subscribe(channel, (message) => {
      try {
        onMessage(JSON.parse(message));
      } catch (_error) {
        // Ignore malformed bridge events rather than destabilizing Socket.IO.
      }
    });
    subscribers.add(subscriber);
    return async () => {
      subscribers.delete(subscriber);
      if (subscriber.isOpen) {
        await subscriber.unsubscribe(channel);
        await subscriber.close();
      }
    };
  } catch (_error) {
    markFailure();
    if (subscriber.isOpen) await subscriber.close();
    return null;
  }
};

const redisGetJson = async (key) =>
  execute(async (activeClient) => {
    const value = await activeClient.get(key);
    if (value == null) return { available: true, value: null };
    try {
      return { available: true, value: JSON.parse(value) };
    } catch (_error) {
      await activeClient.del(key);
      return { available: true, value: null };
    }
  }, { available: false, value: null });

const redisSetJson = async (key, value, ttlSeconds) => {
  if (!Number.isSafeInteger(ttlSeconds) || ttlSeconds < 1) {
    throw new Error('Redis TTL must be a positive integer');
  }
  return execute(async (activeClient) => {
    await activeClient.set(key, JSON.stringify(value), { EX: ttlSeconds });
    return true;
  }, false);
};

const redisDelete = async (...keys) => {
  const filtered = keys.filter(Boolean);
  if (filtered.length === 0) return true;
  return execute(async (activeClient) => {
    await activeClient.del(filtered);
    return true;
  }, false);
};

const acquireRedisLock = async (key, ttlMs) => {
  if (!Number.isSafeInteger(ttlMs) || ttlMs < 100) {
    throw new Error('Redis lock TTL must be at least 100ms');
  }
  const token = crypto.randomUUID();
  const acquired = await execute(
    (activeClient) =>
      activeClient.set(key, token, {
        NX: true,
        PX: ttlMs,
      }),
    null
  );
  return acquired === 'OK' ? token : null;
};

const releaseRedisLock = async (key, token) => {
  if (!token) return false;
  const script = [
    "if redis.call('get', KEYS[1]) == ARGV[1] then",
    "  return redis.call('del', KEYS[1])",
    'end',
    'return 0',
  ].join('\n');
  return execute(
    async (activeClient) =>
      (await activeClient.eval(script, {
        keys: [key],
        arguments: [token],
      })) === 1,
    false
  );
};

const injectRedisClientForTests = ({
  testClient,
  ready = true,
  configured = true,
}) => {
  client = testClient;
  injectedClient = true;
  state = {
    configured,
    ready,
    lastErrorAt: null,
  };
};

const resetRedisForTests = () => {
  client = null;
  injectedClient = false;
  state = {
    configured: Boolean(redisUrl),
    ready: false,
    lastErrorAt: null,
  };
};

module.exports = {
  namespace,
  redisKey,
  executeRedis,
  publishRedisEvent,
  subscribeRedisChannel,
  initializeRedis,
  shutdownRedis,
  getRedisHealth,
  redisGetJson,
  redisSetJson,
  redisDelete,
  acquireRedisLock,
  releaseRedisLock,
  injectRedisClientForTests,
  resetRedisForTests,
};
