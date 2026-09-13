const PushDevice = require('../models/pushDevice');
const { requireSession } = require('./sessionSecurity.service');
const { getFirebaseMessaging } = require('../config/firebaseAdmin');

const sendParaPush = async (notification) => {
  if (notification.type !== 'stop_alert_created') return;
  const messaging = getFirebaseMessaging();
  if (!messaging) return;
  const alertId = String(notification.payload?.stopAlertId || '');
  if (!alertId) return;
  const devices = await PushDevice.find({ userId: notification.userId }).select('+token');
  await Promise.all(devices.map(async (device) => {
    try {
      await requireSession({ sub: String(device.userId), sid: device.sessionId });
    } catch (_) { return; }
    try {
      await messaging.send({
        token: device.token,
        data: { type: 'stop_alert_created', alertId, sessionId: device.sessionId,
          receipt: require('./paraReceipt.service').signParaReceipt({ userId: device.userId, sessionId: device.sessionId, alertId }),
          sentAt: new Date().toISOString() },
        android: { priority: 'high', ttl: 60000, collapseKey: alertId },
      });
    } catch (error) {
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code)) {
        await PushDevice.deleteOne({ _id: device._id, token: device.token });
      }
      // Never log device tokens or turn committed para alerts into failures.
      console.error('[Para push] Delivery failed');
    }
  }));
};
module.exports = { sendParaPush };
