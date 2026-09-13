const express = require('express');
const Notification = require('../models/notification');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const { ok, fail } = require('../utils/response');
const { ensureObjectId } = require('../utils/validators');

const router = express.Router();
router.post('/para/validate', asyncHandler(async (req, res) => {
  if (typeof req.body?.receipt !== 'string' || req.body.receipt.length > 2048) {
    return fail(res, 'Invalid alert authorization', [], 400);
  }
  const result = await require('../services/paraReceipt.service').validateParaReceipt(req.body.receipt);
  return ok(res, result, 'Active para alert');
}));
router.get('/para/:id', authenticate, asyncHandler(async (req, res) => {
  if (req.user.role !== 'DRIVER') return fail(res, 'Forbidden', [], 403);
  ensureObjectId(req.params.id, 'alert id');
  const alert = await require('../models/stopAlert').findById(req.params.id);
  if (!alert || alert.status === 'dismissed') return fail(res, 'Alert unavailable', [], 404);
  const { requireTrip, ensureDriverAssignedToTrip } = require('../services/routeContext.service');
  const trip = await requireTrip(alert.tripSessionId);
  await ensureDriverAssignedToTrip(req.user, trip);
  return ok(res, { active: true }, 'Active para alert');
}));

router.put('/push-device', authenticate, asyncHandler(async (req, res) => {
  if (req.user.role !== 'DRIVER') return fail(res, 'Forbidden', [], 403);
  const token = req.body?.token;
  if (typeof token !== 'string' || token.length < 20 || token.length > 4096 || /\s/.test(token)) {
    return fail(res, 'Invalid push token', [], 400);
  }
  const PushDevice = require('../models/pushDevice');
  const previous = await PushDevice.findOne({ token });
  if (previous && String(previous.userId) === String(req.user._id) && previous.sessionId !== req.authSessionId) {
    try {
      await require('../services/sessionSecurity.service').requireSession({ sub: String(previous.userId), sid: previous.sessionId });
    } catch (error) {
      if (error.statusCode !== 401) throw error;
      await PushDevice.deleteOne({ _id: previous._id, sessionId: previous.sessionId });
    }
  }
  // A token cannot be claimed by another account or session. A fresh login
  // obtains a fresh Firebase token after removing its previous registration.
  try {
    await PushDevice.findOneAndUpdate({ sessionId: req.authSessionId, userId: req.user._id },
      { $set: { token } }, { upsert: true });
  } catch (error) {
    if (error.code === 11000) return fail(res, 'Push token already registered', [], 409);
    throw error;
  }
  return ok(res, {}, 'Push notifications registered');
}));
router.delete('/push-device', authenticate, asyncHandler(async (req, res) => {
  await require('../models/pushDevice').deleteOne({ sessionId: req.authSessionId, userId: req.user._id });
  return ok(res, {}, 'Push notifications disabled');
}));

router.get(
  '/mine',
  authenticate,
  asyncHandler(async (req, res) => {
    const includeRead = String(req.query.includeRead || 'false') === 'true';
    const query = { userId: req.user._id };
    if (!includeRead) query.isRead = false;
    const list = await Notification.find(query).sort({ createdAt: -1 });
    return ok(res, list, 'My notifications');
  })
);

router.patch(
  '/:id/read',
  authenticate,
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'notification id');
    const item = await Notification.findById(req.params.id);
    if (!item) {
      return fail(res, 'Notification not found', [], 404);
    }
    if (String(item.userId) !== String(req.user._id)) {
      return fail(res, 'Forbidden', [], 403);
    }
    item.isRead = true;
    item.readAt = new Date();
    await item.save();
    return ok(res, item, 'Notification marked read');
  })
);

router.patch(
  '/read-all',
  authenticate,
  asyncHandler(async (req, res) => {
    await Notification.updateMany(
      { userId: req.user._id, isRead: false },
      { $set: { isRead: true, readAt: new Date() } }
    );
    return ok(res, null, 'All notifications marked read');
  })
);

module.exports = router;
