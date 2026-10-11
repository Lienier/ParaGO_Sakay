const User = require('../models/user');
const mongoose = require('mongoose');
const Driver = require('../models/driver');
const Passenger = require('../models/passenger');
const Route = require('../models/route');
const TripSession = require('../models/tripSession');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const SupportThread = require('../models/supportThread');
const SupportMessage = require('../models/supportMessage');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');
const { requireCurrentDriver, requireCurrentPassenger } = require('./routeContext.service');
const { publishNotification } = require('./notificationPublisher');
const { emitOperationsChanged, emitToRole, emitToUser } = require('../realtime/socketServer');

const SUPPORT_CATEGORIES = [
  'complaint',
  'lost_item',
  'fare_concern',
  'trip_issue',
  'safety_concern',
  'general_help',
];

const SUPPORT_STATUSES = [
  'open',
  'awaiting_admin',
  'awaiting_user',
  'resolved',
  'closed',
];

const SUPPORT_MESSAGE_ROLES = ['PASSENGER', 'DRIVER', 'ADMIN'];

const normalizeSupportCategory = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  return SUPPORT_CATEGORIES.includes(normalized) ? normalized : 'general_help';
};

const normalizeSupportStatus = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  return SUPPORT_STATUSES.includes(normalized) ? normalized : 'open';
};

const normalizeSupportMessageBody = (value) => {
  const body = String(value || '').trim();
  if (!body) {
    throw new ApiError(400, 'message is required');
  }
  return body;
};

const normalizeSupportSubject = (value) => String(value || '').trim();

const normalizeContextObjectId = (value, fieldName) => {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  ensureObjectId(value, fieldName);
  return String(value);
};

const normalizeThreadRole = (user) => String(user?.role || '').trim().toUpperCase();

const ensureSupportRole = (role) => {
  if (!['PASSENGER', 'DRIVER', 'ADMIN'].includes(role)) {
    throw new ApiError(403, 'You are not allowed to use support chat');
  }
};

const buildThreadPopulate = () => ([
  { path: 'userId', select: 'fullName email role status' },
  { path: 'assignedAdminId', select: 'fullName email role status' },
  { path: 'routeId', select: 'name code status' },
  { path: 'tripSessionId', select: 'status operatingMode routeId driverId startedAt' },
  { path: 'pickupRequestId', select: 'status pickupType tripSessionId routeId stopRef destinationStopRef' },
  { path: 'rideSessionId', select: 'status tripSessionId pickupRequestId boardingMethod' },
]);

const summarizeThread = (thread) => {
  if (!thread) return null;
  const raw = typeof thread.toObject === 'function' ? thread.toObject() : thread;
  return {
    ...raw,
    id: raw._id?.toString() || '',
  };
};

const summarizeMessage = (message) => {
  if (!message) return null;
  const raw = typeof message.toObject === 'function' ? message.toObject() : message;
  return {
    ...raw,
    id: raw._id?.toString() || '',
  };
};

const populateThread = async (thread) => {
  if (!thread) return null;
  return thread.populate(buildThreadPopulate());
};

const validatePassengerContext = async ({ passenger, tripSessionId, pickupRequestId, rideSessionId }) => {
  let pickupRequest = null;
  let rideSession = null;
  let tripSession = null;

  if (pickupRequestId) {
    pickupRequest = await PickupRequest.findById(pickupRequestId);
    if (!pickupRequest) {
      throw new ApiError(404, 'Pickup request not found');
    }
    if (String(pickupRequest.passengerId) !== String(passenger._id)) {
      throw new ApiError(403, 'You can only link your own pickup requests');
    }
  }

  if (rideSessionId) {
    rideSession = await RideSession.findById(rideSessionId);
    if (!rideSession) {
      throw new ApiError(404, 'Ride session not found');
    }
    if (String(rideSession.passengerId) !== String(passenger._id)) {
      throw new ApiError(403, 'You can only link your own ride sessions');
    }
  }

  if (tripSessionId) {
    tripSession = await TripSession.findById(tripSessionId);
    if (!tripSession) {
      throw new ApiError(404, 'Trip session not found');
    }
    const pickupMatches = pickupRequest && String(pickupRequest.tripSessionId) === String(tripSessionId);
    const rideMatches = rideSession && String(rideSession.tripSessionId) === String(tripSessionId);
    if (!pickupMatches && !rideMatches) {
      throw new ApiError(
        409,
        'Passenger support threads must be linked to one of your pickup requests or ride sessions'
      );
    }
  }

  if (!tripSession && pickupRequest) {
    tripSession = await TripSession.findById(pickupRequest.tripSessionId);
  }
  if (!tripSession && rideSession) {
    tripSession = await TripSession.findById(rideSession.tripSessionId);
  }

  const routeId = tripSession?.routeId || pickupRequest?.routeId || null;
  return {
    tripSessionId: tripSession?._id || null,
    pickupRequestId: pickupRequest?._id || null,
    rideSessionId: rideSession?._id || null,
    routeId: routeId ? String(routeId) : null,
  };
};

const validateDriverContext = async ({ driver, tripSessionId, routeId }) => {
  if (!tripSessionId) {
    if (routeId && String(routeId) !== String(driver.assignedRouteId)) {
      throw new ApiError(403, 'You can only link your assigned route');
    }
    return { tripSessionId: null, routeId: routeId || driver.assignedRouteId || null };
  }

  const tripSession = await TripSession.findById(tripSessionId);
  if (!tripSession) {
    throw new ApiError(404, 'Trip session not found');
  }

  if (String(tripSession.driverId) !== String(driver._id)) {
    throw new ApiError(403, 'You can only open support threads for your own trip sessions');
  }

  const resolvedRouteId = routeId || tripSession.routeId;
  return {
    tripSessionId: tripSession._id,
    routeId: resolvedRouteId ? String(resolvedRouteId) : null,
  };
};

const resolveThreadContext = async ({ user, tripSessionId, pickupRequestId, rideSessionId, routeId }) => {
  const role = normalizeThreadRole(user);
  if (role === 'ADMIN') {
    return {
      tripSessionId: normalizeContextObjectId(tripSessionId, 'tripSessionId'),
      pickupRequestId: normalizeContextObjectId(pickupRequestId, 'pickupRequestId'),
      rideSessionId: normalizeContextObjectId(rideSessionId, 'rideSessionId'),
      routeId: normalizeContextObjectId(routeId, 'routeId'),
    };
  }

  if (role === 'PASSENGER') {
    const passenger = await requireCurrentPassenger(user);
    const resolved = await validatePassengerContext({
      passenger,
      tripSessionId: normalizeContextObjectId(tripSessionId, 'tripSessionId'),
      pickupRequestId: normalizeContextObjectId(pickupRequestId, 'pickupRequestId'),
      rideSessionId: normalizeContextObjectId(rideSessionId, 'rideSessionId'),
    });
    return {
      ...resolved,
      routeId: resolved.routeId || normalizeContextObjectId(routeId, 'routeId'),
    };
  }

  const driver = await requireCurrentDriver(user);
  const resolved = await validateDriverContext({
    driver,
    tripSessionId: normalizeContextObjectId(tripSessionId, 'tripSessionId'),
    routeId: normalizeContextObjectId(routeId, 'routeId'),
  });
  return resolved;
};

const resolveThreadAccess = async ({ user, threadId, allowAdmin = true }) => {
  ensureObjectId(threadId, 'thread id');
  const thread = await SupportThread.findById(threadId);
  if (!thread) {
    throw new ApiError(404, 'Support thread not found');
  }

  const role = normalizeThreadRole(user);
  if (role === 'ADMIN' && allowAdmin) {
    return thread;
  }

  if (String(thread.userId) !== String(user._id)) {
    throw new ApiError(403, 'You are not allowed to access this support thread');
  }

  return thread;
};

const getActiveAdminUsers = async () =>
  User.find({ role: 'ADMIN', status: 'active' }).select('_id fullName email role');

const emitSupportThreadEvent = async ({ thread, eventName, userId = null }) => {
  const serialized = summarizeThread(thread);
  if (!serialized) return;
  const eventPayload = {
    ...serialized,
    eventName,
    notificationType: eventName,
    threadId: serialized.id,
  };
  emitOperationsChanged({
    notificationType: eventName,
    payload: {
      threadId: serialized.id,
      userId: serialized.userId?.toString?.() || serialized.userId,
      status: serialized.status,
      category: serialized.category,
    },
    userId: userId ? String(userId) : undefined,
  });
  emitToRole('admin', eventName, eventPayload);
  if (userId) {
    emitToUser(userId, eventName, eventPayload);
  }
};

const sendSupportNotifications = async ({ thread, message, senderRole }) => {
  const serializedThread = summarizeThread(thread);
  if (!serializedThread) return;

  if (senderRole === 'ADMIN') {
    await publishNotification({
      userId: serializedThread.userId,
      type: 'support_message_received',
      title: 'Support reply received',
      body: `An admin replied to your ${serializedThread.category.replace(/_/g, ' ')} thread.`,
      payload: {
        threadId: serializedThread.id,
        thread: serializedThread,
        message: summarizeMessage(message),
      },
      category: 'support',
    });
    return;
  }

  const admins = await getActiveAdminUsers();
  await Promise.all(
    admins.map((admin) =>
      publishNotification({
        userId: admin._id,
        type: 'support_thread_activity',
        title: 'New support message',
        body: `${serializedThread.userRole?.toLowerCase() || 'A user'} sent a new support message.`,
        payload: {
          threadId: serializedThread.id,
          thread: serializedThread,
          message: summarizeMessage(message),
        },
        category: 'support',
      })
    )
  );
};

const createSupportThread = async ({ user, subject, category, message, tripSessionId, pickupRequestId, rideSessionId, routeId }) => {
  const role = normalizeThreadRole(user);
  ensureSupportRole(role);
  const messageBody = normalizeSupportMessageBody(message);

  const context = await resolveThreadContext({
    user,
    tripSessionId,
    pickupRequestId,
    rideSessionId,
    routeId,
  });

  const session = await mongoose.startSession();
  let thread, supportMessage;
  try { await session.withTransaction(async () => {
  [thread] = await SupportThread.create([{
    userId: user._id,
    userRole: role,
    subject: normalizeSupportSubject(subject),
    category: normalizeSupportCategory(category),
    status: 'open',
    tripSessionId: context.tripSessionId || undefined,
    pickupRequestId: context.pickupRequestId || undefined,
    rideSessionId: context.rideSessionId || undefined,
    routeId: context.routeId || undefined,
    unreadAdminCount: 1,
    unreadUserCount: 0,
    lastMessageAt: new Date(),
    lastMessagePreview: messageBody.slice(0, 160),
    lastMessageSenderRole: role,
  }], { session });

  [supportMessage] = await SupportMessage.create([{
    threadId: thread._id,
    senderId: user._id,
    senderRole: role,
    body: messageBody,
  }], { session });

  thread.subject = thread.subject || thread.category.replace(/_/g, ' ');
  thread.lastMessageAt = supportMessage.createdAt || new Date();
  thread.lastMessagePreview = supportMessage.body.slice(0, 160);
  thread.lastMessageSenderRole = role;
  await thread.save({ session });
  }); } finally { await session.endSession(); }

  const populatedThread = await populateThread(thread);
  await sendSupportNotifications({
    thread: populatedThread,
    message: supportMessage,
    senderRole: role,
  }).catch(() => console.error('[Support] Notification delivery failed after the thread was saved'));
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.thread.created',
    userId: role === 'ADMIN' ? null : user._id,
  });

  return {
    thread: summarizeThread(populatedThread),
    message: summarizeMessage(supportMessage),
  };
};

const listUserSupportThreads = async ({ user, includeClosed = false }) => {
  const query = {
    userId: user._id,
    ...(includeClosed ? {} : { status: { $ne: 'closed' } }),
  };
  const threads = await SupportThread.find(query)
    .sort({ lastMessageAt: -1, createdAt: -1 })
    .populate(buildThreadPopulate());
  return threads.map(summarizeThread);
};

const listAdminSupportThreads = async ({ status, category, userRole, assignedAdminId, includeClosed = true } = {}) => {
  const query = {};
  if (status) query.status = normalizeSupportStatus(status);
  if (category && String(category).trim()) query.category = normalizeSupportCategory(category);
  if (userRole) query.userRole = String(userRole).trim().toUpperCase();
  if (assignedAdminId) query.assignedAdminId = String(assignedAdminId);
  if (!includeClosed && !status) {
    query.status = { $ne: 'closed' };
  }
  const threads = await SupportThread.find(query)
    .sort({ lastMessageAt: -1, createdAt: -1 })
    .populate(buildThreadPopulate());
  return threads.map(summarizeThread);
};

const listThreadMessages = async ({ user, threadId }) => {
  const thread = await resolveThreadAccess({ user, threadId });
  const messages = await SupportMessage.find({ threadId: thread._id }).sort({ createdAt: 1 }).populate(
    'senderId',
    'fullName email role'
  );
  return {
    thread: summarizeThread(await populateThread(thread)),
    messages: messages.map(summarizeMessage),
  };
};

const addSupportMessage = async ({ user, threadId, body }) => {
  let thread = await resolveThreadAccess({ user, threadId });
  const role = normalizeThreadRole(user);
  ensureSupportRole(role);

  if (thread.status === 'closed') {
    throw new ApiError(409, 'Closed support threads must be reopened before sending new messages');
  }

  const messageBody = normalizeSupportMessageBody(body);
  const session = await mongoose.startSession();
  let message;
  try { await session.withTransaction(async () => {
  const now = new Date();
  thread = await SupportThread.findOneAndUpdate({ _id: threadId, status: { $ne: 'closed' } }, {
    $set: { lastMessageAt: now, lastMessagePreview: messageBody.slice(0, 160), lastMessageSenderRole: role,
      status: role === 'ADMIN' ? 'awaiting_user' : 'awaiting_admin',
      ...(role === 'ADMIN' ? { unreadAdminCount: 0, lastAdminReadAt: now } : { unreadUserCount: 0, lastUserReadAt: now }),
    },
    $inc: role === 'ADMIN' ? { unreadUserCount: 1 } : { unreadAdminCount: 1 },
  }, { new: true, session });
  if (!thread) throw new ApiError(409, 'Closed support threads must be reopened before sending new messages');
  [message] = await SupportMessage.create([{
    threadId: thread._id,
    senderId: user._id,
    senderRole: role,
    body: messageBody,
  }], { session });
  }); } finally { await session.endSession(); }

  const populatedThread = await populateThread(thread);
  await sendSupportNotifications({
    thread: populatedThread,
    message,
    senderRole: role,
  }).catch(() => console.error('[Support] Notification delivery failed after the message was saved'));
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.message.created',
    userId: String(thread.userId),
  });

  return {
    thread: summarizeThread(populatedThread),
    message: summarizeMessage(message),
  };
};

const markSupportThreadRead = async ({ user, threadId }) => {
  const thread = await resolveThreadAccess({ user, threadId });
  const role = normalizeThreadRole(user);
  ensureSupportRole(role);
  const now = new Date();

  if (role === 'ADMIN') {
    thread.unreadAdminCount = 0;
    thread.lastAdminReadAt = now;
  } else {
    thread.unreadUserCount = 0;
    thread.lastUserReadAt = now;
  }
  await thread.save();

  const populatedThread = await populateThread(thread);
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.thread.read',
    userId: String(thread.userId),
  });
  return summarizeThread(populatedThread);
};

const closeSupportThread = async ({ user, threadId, reason = '' }) => {
  const thread = await resolveThreadAccess({ user, threadId });
  const now = new Date();
  thread.status = 'closed';
  thread.closedAt = now;
  thread.closedByUserId = user._id;
  thread.lastMessagePreview = thread.lastMessagePreview || normalizeSupportSubject(reason);
  await thread.save();
  const populatedThread = await populateThread(thread);
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.thread.updated',
    userId: String(thread.userId),
  });
  return summarizeThread(populatedThread);
};

const reopenSupportThread = async ({ user, threadId }) => {
  const thread = await resolveThreadAccess({ user, threadId });
  const now = new Date();
  thread.status = 'awaiting_admin';
  thread.reopenedAt = now;
  thread.reopenedByUserId = user._id;
  thread.closedAt = undefined;
  thread.closedByUserId = undefined;
  thread.unreadAdminCount = (thread.unreadAdminCount || 0) + 1;
  await thread.save();
  const populatedThread = await populateThread(thread);
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.thread.updated',
    userId: String(thread.userId),
  });
  return summarizeThread(populatedThread);
};

const resolveSupportThread = async ({ user, threadId, status = 'resolved' }) => {
  const thread = await resolveThreadAccess({ user, threadId });
  const role = normalizeThreadRole(user);
  if (role !== 'ADMIN') {
    throw new ApiError(403, 'Only admins can resolve support threads');
  }
  const normalizedStatus = normalizeSupportStatus(status);
  thread.status = normalizedStatus === 'closed' ? 'closed' : 'resolved';
  thread.resolvedAt = new Date();
  thread.resolvedByUserId = user._id;
  thread.unreadUserCount = (thread.unreadUserCount || 0) + 1;
  await thread.save();
  const populatedThread = await populateThread(thread);
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.thread.updated',
    userId: String(thread.userId),
  });
  return summarizeThread(populatedThread);
};

const assignSupportThread = async ({ user, threadId, assignedAdminId }) => {
  const thread = await resolveThreadAccess({ user, threadId });
  const role = normalizeThreadRole(user);
  if (role !== 'ADMIN') {
    throw new ApiError(403, 'Only admins can assign support threads');
  }
  const adminId = normalizeContextObjectId(assignedAdminId, 'assignedAdminId');
  if (adminId) {
    const assignedAdmin = await User.findOne({
      _id: adminId,
      role: 'ADMIN',
      status: 'active',
    }).select('_id fullName email role');
    if (!assignedAdmin) {
      throw new ApiError(404, 'Assigned admin not found');
    }
    thread.assignedAdminId = assignedAdmin._id;
  } else {
    thread.assignedAdminId = undefined;
  }
  await thread.save();
  const populatedThread = await populateThread(thread);
  await emitSupportThreadEvent({
    thread: populatedThread,
    eventName: 'support.thread.updated',
    userId: String(thread.userId),
  });
  return summarizeThread(populatedThread);
};

module.exports = {
  SUPPORT_CATEGORIES,
  SUPPORT_STATUSES,
  SUPPORT_MESSAGE_ROLES,
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
};
