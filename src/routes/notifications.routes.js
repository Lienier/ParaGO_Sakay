const express = require('express');
const Notification = require('../models/notification');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const { ok, fail } = require('../utils/response');
const { ensureObjectId } = require('../utils/validators');

const router = express.Router();

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
