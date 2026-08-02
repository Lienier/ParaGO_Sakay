const {
  redisKey,
  publishRedisEvent,
  subscribeRedisChannel,
} = require('./redis.service');

const channel = redisKey('events', 'operations');

const publishOperationalEvent = async ({
  target,
  targetId,
  eventName,
  payload,
}) => {
  if (!target || !targetId || !eventName) return false;
  return publishRedisEvent(channel, {
    target: String(target),
    targetId: String(targetId),
    eventName: String(eventName),
    payload,
    publishedAt: new Date().toISOString(),
  });
};

const startOperationalEventSubscriber = async (onEvent) =>
  subscribeRedisChannel(channel, onEvent);

module.exports = {
  operationalEventChannel: channel,
  publishOperationalEvent,
  startOperationalEventSubscriber,
};
