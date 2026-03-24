const Notification = require('../models/notification');
const { emitNotificationCreated } = require('../realtime/socketServer');

const safePayload = (value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value;
};

const publishNotification = async ({
  userId,
  type,
  title,
  body,
  payload = {},
  category = 'system',
  expiresAt = null,
}) => {
  if (!userId) return null;
  if (!type || !title || !body) return null;
  const notification = await Notification.create({
    userId,
    type: String(type).toLowerCase(),
    title: String(title),
    body: String(body),
    payload: safePayload(payload),
    category: String(category || 'system').trim(),
    ...(expiresAt ? { expiresAt } : {}),
  });

  emitNotificationCreated(notification);
  return notification;
};

module.exports = {
  publishNotification,
};
