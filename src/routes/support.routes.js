const express = require('express');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/apiError');
const { ok } = require('../utils/response');
const { PASSENGER, DRIVER, ADMIN } = require('../constants/roles');
const {
  SUPPORT_CATEGORIES,
  createSupportThread,
  listUserSupportThreads,
  listAdminSupportThreads,
  listThreadMessages,
  addSupportMessage,
  markSupportThreadRead,
  closeSupportThread,
  reopenSupportThread,
  resolveSupportThread,
  assignSupportThread,
  normalizeSupportCategory,
  normalizeSupportStatus,
} = require('../services/support.service');
const { ensureObjectId } = require('../utils/validators');

const router = express.Router();

const normalizeOptionalText = (value) => String(value || '').trim();
const normalizeIncludeClosed = (value) => String(value || 'false').toLowerCase() === 'true';

router.post(
  '/threads',
  authenticate,
  authorize(PASSENGER, DRIVER),
  asyncHandler(async (req, res) => {
    const payload = req.body || {};
    const created = await createSupportThread({
      user: req.user,
      subject: payload.subject,
      category: payload.category,
      message: payload.message,
      tripSessionId: payload.tripSessionId,
      pickupRequestId: payload.pickupRequestId,
      rideSessionId: payload.rideSessionId,
      routeId: payload.routeId,
    });

    return ok(res, created, 'Support thread created', 201);
  })
);

router.get(
  '/threads',
  authenticate,
  authorize(PASSENGER, DRIVER),
  asyncHandler(async (req, res) => {
    const threads = await listUserSupportThreads({
      user: req.user,
      includeClosed: normalizeIncludeClosed(req.query.includeClosed),
    });
    return ok(res, threads, 'My support threads');
  })
);

router.get(
  '/threads/:id/messages',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const data = await listThreadMessages({
      user: req.user,
      threadId: req.params.id,
    });
    return ok(res, data, 'Support thread messages');
  })
);

router.post(
  '/threads/:id/messages',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const payload = req.body || {};
    const data = await addSupportMessage({
      user: req.user,
      threadId: req.params.id,
      body: payload.body,
    });
    return ok(res, data, 'Support message sent', 201);
  })
);

router.patch(
  '/threads/:id/read',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const thread = await markSupportThreadRead({
      user: req.user,
      threadId: req.params.id,
    });
    return ok(res, thread, 'Support thread marked read');
  })
);

router.patch(
  '/threads/:id/close',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const thread = await closeSupportThread({
      user: req.user,
      threadId: req.params.id,
      reason: req.body?.reason,
    });
    return ok(res, thread, 'Support thread closed');
  })
);

router.patch(
  '/threads/:id/reopen',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const thread = await reopenSupportThread({
      user: req.user,
      threadId: req.params.id,
    });
    return ok(res, thread, 'Support thread reopened');
  })
);

router.get(
  '/admin/threads',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    const status = normalizeOptionalText(req.query.status);
    const category = normalizeOptionalText(req.query.category);
    const userRole = normalizeOptionalText(req.query.userRole);
    const assignedAdminId = normalizeOptionalText(req.query.assignedAdminId);
    const threads = await listAdminSupportThreads({
      ...(status ? { status: normalizeSupportStatus(status) } : {}),
      ...(category ? { category: normalizeSupportCategory(category) } : {}),
      ...(userRole ? { userRole } : {}),
      ...(assignedAdminId ? { assignedAdminId } : {}),
      includeClosed: normalizeIncludeClosed(req.query.includeClosed),
    });
    return ok(res, threads, 'Support inbox');
  })
);

router.patch(
  '/admin/threads/:id/assign',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const thread = await assignSupportThread({
      user: req.user,
      threadId: req.params.id,
      assignedAdminId: req.body?.assignedAdminId,
    });
    return ok(res, thread, 'Support thread assigned');
  })
);

router.patch(
  '/admin/threads/:id/resolve',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'thread id');
    const thread = await resolveSupportThread({
      user: req.user,
      threadId: req.params.id,
      status: req.body?.status || 'resolved',
    });
    return ok(res, thread, 'Support thread resolved');
  })
);

router.get(
  '/categories',
  authenticate,
  authorize(PASSENGER, DRIVER, ADMIN),
  asyncHandler(async (_req, res) => {
    return ok(res, { categories: SUPPORT_CATEGORIES }, 'Support categories');
  })
);

module.exports = router;
