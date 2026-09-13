const Notification = require('../models/notification');
const {
  emitNotificationCreated,
  emitOperationsChanged,
} = require('../realtime/socketServer');

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
  if (notification.type === 'stop_alert_created') {
    void require('./paraPush.service').sendParaPush(notification).catch(() => {
      console.error('[Para push] Dispatch failed');
    });
  }
  emitOperationsChanged({
    type: 'notification.created',
    notificationId: notification._id.toString(),
    userId: notification.userId.toString(),
    notificationType: notification.type,
    title: notification.title,
    body: notification.body,
    category: notification.category,
    payload: notification.payload && typeof notification.payload === 'object'
      ? notification.payload
      : {},
    createdAt: notification.createdAt
      ? new Date(notification.createdAt).toISOString()
      : new Date().toISOString(),
  });
  return notification;
};

module.exports = {
  publishNotification,
};
