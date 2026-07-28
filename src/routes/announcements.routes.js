const express = require('express');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/response');
const { ensureObjectId } = require('../utils/validators');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const {
  listActiveAnnouncements,
  dismissAnnouncement,
  listAdminAnnouncements,
  createAnnouncement,
  updateAnnouncement,
  archiveAnnouncement,
} = require('../services/announcement.service');

const router = express.Router();

router.get(
  '/active',
  authenticate,
  authorize(PASSENGER, DRIVER),
  asyncHandler(async (req, res) => {
    const list = await listActiveAnnouncements({ user: req.user });
    return ok(res, list, 'Active announcements');
  })
);

router.post(
  '/:id/dismiss',
  authenticate,
  authorize(PASSENGER, DRIVER),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'announcement id');
    const dismissal = await dismissAnnouncement({
      user: req.user,
      announcementId: req.params.id,
      revision: req.body?.revision,
    });
    return ok(res, dismissal, 'Announcement dismissed');
  })
);

router.get(
  '/admin',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const list = await listAdminAnnouncements({ filters: req.query });
    return ok(res, list, 'Announcements');
  })
);

router.post(
  '/admin',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const announcement = await createAnnouncement({
      admin: req.user,
      input: req.body || {},
    });
    return ok(res, announcement, 'Announcement created', 201);
  })
);

router.patch(
  '/admin/:id',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'announcement id');
    const announcement = await updateAnnouncement({
      admin: req.user,
      announcementId: req.params.id,
      input: req.body || {},
    });
    return ok(res, announcement, 'Announcement updated');
  })
);

router.post(
  '/admin/:id/archive',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'announcement id');
    const announcement = await archiveAnnouncement({
      admin: req.user,
      announcementId: req.params.id,
      confirmActiveArchive: req.body?.confirmActiveArchive,
    });
    return ok(res, announcement, 'Announcement archived');
  })
);

module.exports = router;
