const { requireSession, revocationChannel } = require('../services/sessionSecurity.service');
const { subscribeRedisChannel } = require('../services/redis.service');
let stopSecuritySubscriber;
const { Server } = require('socket.io');
const mongoose = require('mongoose');

const User = require('../models/user');
const { verifyAccessToken } = require('../utils/jwt');
const { createCorsOriginDelegate } = require('../utils/cors');
const {
  authorizeRouteSubscription,
  authorizeTripSubscription,
} = require('./subscriptionAuthorizer');
const { RouteLocationBatcher } = require('./routeLocationBatcher');
const {
  publishOperationalEvent,
  startOperationalEventSubscriber,
} = require('../services/operationalEventBridge.service');

let ioInstance = null;
let routeLocationBatcher = null;
let stopOperationalEventSubscriber = null;
const subscriptionWindowMs = 10_000;
const maxSubscriptionEventsPerWindow = 20;
const maxCustomRoomsPerSocket = 8;

const normalizeRoomKey = (value) => String(value || '').trim();
const safeResourceId = (value) => normalizeRoomKey(value).slice(0, 64);
const toUserRoom = (userId) => `user:${String(userId)}`;
const toRoleRoom = (role) => `role:${String(role || '').trim().toLowerCase()}`;
const toRouteRoom = (routeId) => `route:${normalizeRoomKey(routeId)}`;
const toTripRoom = (tripId) => `trip:${normalizeRoomKey(tripId)}`;

const extractToken = (socket) => {
  const authToken = socket.handshake.auth?.token;
  if (typeof authToken === 'string' && authToken.trim()) {
    return authToken.trim();
  }

  const header = socket.handshake.headers?.authorization;
  if (typeof header === 'string' && header.startsWith('Bearer ')) {
    return header.slice(7).trim();
  }

  return '';
};

const serializeNotification = (notification) => {
  if (!notification) return null;
  const raw =
    typeof notification.toObject === 'function'
      ? notification.toObject()
      : notification;

  return {
    id: raw._id?.toString() || '',
    userId: raw.userId?.toString() || '',
    type: raw.type?.toString() || '',
    title: raw.title?.toString() || '',
    body: raw.body?.toString() || '',
    category: raw.category?.toString() || '',
    isRead: Boolean(raw.isRead),
    createdAt: raw.createdAt ? new Date(raw.createdAt).toISOString() : null,
    payload:
      raw.payload && typeof raw.payload === 'object' && !Array.isArray(raw.payload)
        ? raw.payload
        : {},
  };
};

const withRoomKey = (value, callback) => {
  const roomKey = normalizeRoomKey(value);
  if (!roomKey) return;
  callback(roomKey);
};

const acknowledgement = (callback, payload) => {
  if (typeof callback === 'function') {
    callback(payload);
  }
};

const securityLog = (socket, eventName, reason, resourceId = '') => {
  const entry = {
    type: 'socket.subscription.rejected',
    eventName,
    reason,
    userId: socket.data.user?.id || null,
    role: socket.data.user?.role || null,
    socketId: socket.id,
    resourceId: safeResourceId(resourceId) || null,
    occurredAt: new Date().toISOString(),
  };
  console.warn(JSON.stringify(entry));
};

const rejectSubscription = (
  socket,
  eventName,
  callback,
  { code, message, resourceId = '' }
) => {
  const payload = {
    ok: false,
    eventName,
    code,
    message,
    resourceId: safeResourceId(resourceId),
  };
  securityLog(socket, eventName, code, resourceId);
  acknowledgement(callback, payload);
  return payload;
};

const consumeSubscriptionEvent = (socket) => {
  const now = Date.now();
  const current = socket.data.subscriptionRate || {
    windowStartedAt: now,
    count: 0,
  };
  if (now - current.windowStartedAt >= subscriptionWindowMs) {
    current.windowStartedAt = now;
    current.count = 0;
  }
  current.count += 1;
  socket.data.subscriptionRate = current;
  return current.count <= maxSubscriptionEventsPerWindow;
};

const isValidResourceId = (value) =>
  mongoose.isObjectIdOrHexString(normalizeRoomKey(value));

const removeTrackedRoom = async (socket, roomName) => {
  await socket.leave(roomName);
  socket.data.customRooms?.delete(roomName);
};

const replacePassengerRouteRoom = async (socket, nextRoomName) => {
  if (socket.data.user?.role !== 'PASSENGER') return null;
  const currentRouteRoom = Array.from(socket.data.customRooms || []).find(
    (roomName) => roomName.startsWith('route:') && roomName !== nextRoomName
  );
  if (!currentRouteRoom) return null;
  await removeTrackedRoom(socket, currentRouteRoom);
  return currentRouteRoom.slice('route:'.length);
};

const subscribeToResource = async ({
  socket,
  eventName,
  resourceType,
  resourceId,
  callback,
  authorize,
  toRoom,
}) => {
  const normalizedId = normalizeRoomKey(resourceId);
  if (!consumeSubscriptionEvent(socket)) {
    return rejectSubscription(socket, eventName, callback, {
      code: 'RATE_LIMITED',
      message: 'Too many subscription requests',
      resourceId: normalizedId,
    });
  }
  if (!isValidResourceId(normalizedId)) {
    return rejectSubscription(socket, eventName, callback, {
      code: 'INVALID_IDENTIFIER',
      message: `Invalid ${resourceType} identifier`,
      resourceId: normalizedId,
    });
  }

  let authorization;
  try {
    authorization = await authorize({
      user: socket.data.user,
      [`${resourceType}Id`]: normalizedId,
    });
  } catch (_error) {
    return rejectSubscription(socket, eventName, callback, {
      code: 'AUTHORIZATION_UNAVAILABLE',
      message: 'Subscription authorization is temporarily unavailable',
      resourceId: normalizedId,
    });
  }
  if (!authorization.allowed) {
    return rejectSubscription(socket, eventName, callback, {
      code: authorization.code || 'FORBIDDEN',
      message: 'You are not authorized for this subscription',
      resourceId: normalizedId,
    });
  }

  const roomName = toRoom(normalizedId);
  const replacedRouteId =
    resourceType === 'route'
      ? await replacePassengerRouteRoom(socket, roomName)
      : null;
  const isAlreadyJoined = socket.data.customRooms.has(roomName);
  if (
    !isAlreadyJoined &&
    socket.data.customRooms.size >= maxCustomRoomsPerSocket
  ) {
    return rejectSubscription(socket, eventName, callback, {
      code: 'ROOM_LIMIT',
      message: 'Socket subscription room limit reached',
      resourceId: normalizedId,
    });
  }

  await socket.join(roomName);
  socket.data.customRooms.add(roomName);
  const payload = {
    ok: true,
    eventName,
    resourceType,
    resourceId: normalizedId,
    alreadySubscribed: isAlreadyJoined,
    ...(replacedRouteId ? { replacedRouteId } : {}),
  };
  acknowledgement(callback, payload);
  return payload;
};

const unsubscribeFromResource = async ({
  socket,
  eventName,
  resourceType,
  resourceId,
  callback,
  toRoom,
}) => {
  const normalizedId = normalizeRoomKey(resourceId);
  if (!consumeSubscriptionEvent(socket)) {
    return rejectSubscription(socket, eventName, callback, {
      code: 'RATE_LIMITED',
      message: 'Too many subscription requests',
      resourceId: normalizedId,
    });
  }
  if (!isValidResourceId(normalizedId)) {
    return rejectSubscription(socket, eventName, callback, {
      code: 'INVALID_IDENTIFIER',
      message: `Invalid ${resourceType} identifier`,
      resourceId: normalizedId,
    });
  }

  const roomName = toRoom(normalizedId);
  const wasSubscribed = socket.data.customRooms.has(roomName);
  await removeTrackedRoom(socket, roomName);
  const payload = {
    ok: true,
    eventName,
    resourceType,
    resourceId: normalizedId,
    wasSubscribed,
  };
  acknowledgement(callback, payload);
  return payload;
};

const attachSocketServer = (httpServer, { corsOrigins = [] } = {}) => {
  if (ioInstance) {
    return ioInstance;
  }

  const io = new Server(httpServer, {
    cors: {
      origin: createCorsOriginDelegate({
        allowedOrigins: corsOrigins,
      }),
      methods: ['GET', 'POST'],
    },
    transports: ['websocket', 'polling'],
    path: '/socket.io',
    pingInterval: 25000,
    pingTimeout: 60000,
  });
  routeLocationBatcher = new RouteLocationBatcher({
    onBatch: (payload) => {
      emitToRoute(payload.routeId, 'route.vehicles.updated', payload);
    },
  });

  io.use(async (socket, next) => {
    const token = extractToken(socket);
    if (!token) {
      next(new Error('Authentication token missing'));
      return;
    }

    try {
      const payload = verifyAccessToken(token);
      const { user } = await requireSession(payload);
      socket.data.claims = payload;
      if (!user || user.status !== 'active') {
        next(new Error('Invalid user session'));
        return;
      }
      socket.data.user = {
        id: user._id.toString(),
        fullName: user.fullName,
        role: user.role,
      };
      socket.data.customRooms = new Set();
      next();
    } catch (_error) {
      next(new Error('Invalid or expired token'));
    }
  });

  void subscribeRedisChannel(revocationChannel, ({ userId, sessionId, reason }) => {
    for (const socket of io.sockets.sockets.values()) {
      if (socket.data.claims?.sub === userId && (!sessionId || socket.data.claims?.sid === sessionId)) {
        if (reason === 'replaced') {
          // Revalidate instead of trusting event order: a newer valid login
          // must survive a delayed event from an earlier competing login.
          void requireSession(socket.data.claims).catch(() => socket.disconnect(true));
        } else socket.disconnect(true);
      }
    }
  }).then((stop) => { stopSecuritySubscriber = stop; });
  io.on('connection', (socket) => {
    const expiryTimer = setTimeout(() => socket.disconnect(true),
      Math.max(1, socket.data.claims.exp * 1000 - Date.now()));
    const validationTimer = setInterval(() => {
      const deadline = setTimeout(() => socket.disconnect(true), 5000);
      void requireSession(socket.data.claims).catch(() => socket.disconnect(true)).finally(() => clearTimeout(deadline));
    }, 20000);
    expiryTimer.unref?.();
    validationTimer.unref?.();
    socket.on('disconnect', () => { clearTimeout(expiryTimer); clearInterval(validationTimer); });
    const userId = socket.data.user?.id;
    const role = socket.data.user?.role;
    if (userId) {
      socket.join(toUserRoom(userId));
      if (role) {
        socket.join(toRoleRoom(role));
      }
      socket.emit('socket.ready', {
        userId,
        connectedAt: new Date().toISOString(),
      });
    }

    socket.on('subscribe.route', (routeId, callback) => {
      void subscribeToResource({
        socket,
        eventName: 'subscribe.route',
        resourceType: 'route',
        resourceId: routeId,
        callback,
        authorize: authorizeRouteSubscription,
        toRoom: toRouteRoom,
      }).then((result) => {
        if (!result?.ok) return;
        const snapshot = routeLocationBatcher?.snapshot(result.resourceId);
        if (snapshot) {
          socket.emit('route.vehicles.updated', snapshot);
        }
      });
    });

    socket.on('subscribe.trip', (tripId, callback) => {
      void subscribeToResource({
        socket,
        eventName: 'subscribe.trip',
        resourceType: 'trip',
        resourceId: tripId,
        callback,
        authorize: authorizeTripSubscription,
        toRoom: toTripRoom,
      });
    });

    socket.on('unsubscribe.route', (routeId, callback) => {
      void unsubscribeFromResource({
        socket,
        eventName: 'unsubscribe.route',
        resourceType: 'route',
        resourceId: routeId,
        callback,
        toRoom: toRouteRoom,
      });
    });

    socket.on('unsubscribe.trip', (tripId, callback) => {
      void unsubscribeFromResource({
        socket,
        eventName: 'unsubscribe.trip',
        resourceType: 'trip',
        resourceId: tripId,
        callback,
        toRoom: toTripRoom,
      });
    });
  });

  ioInstance = io;
  void startOperationalEventSubscriber((event) => {
    if (!event?.eventName || !event?.targetId) return;
    if (event.target === 'user') {
      emitToUserLocal(event.targetId, event.eventName, event.payload);
    } else if (event.target === 'role') {
      emitToRoleLocal(event.targetId, event.eventName, event.payload);
    } else if (event.target === 'trip') {
      emitToTripLocal(event.targetId, event.eventName, event.payload);
    } else if (event.target === 'route') {
      emitToRouteLocal(event.targetId, event.eventName, event.payload);
    }
  }).then((stop) => {
    stopOperationalEventSubscriber = stop;
  });
  return io;
};

const emitToUserLocal = (userId, eventName, payload) => {
  if (!ioInstance || !userId || !eventName) return false;
  ioInstance.to(toUserRoom(userId)).emit(eventName, payload);
  return true;
};

const emitToUser = (userId, eventName, payload) => {
  if (!userId || !eventName) return;
  if (emitToUserLocal(userId, eventName, payload)) return;
  void publishOperationalEvent({
    target: 'user',
    targetId: userId,
    eventName,
    payload,
  });
};

const emitToRoleLocal = (role, eventName, payload) => {
  const normalizedRole = String(role || '').trim().toLowerCase();
  if (!ioInstance || !normalizedRole || !eventName) return false;
  ioInstance.to(toRoleRoom(normalizedRole)).emit(eventName, payload);
  return true;
};

const emitToRole = (role, eventName, payload) => {
  const normalizedRole = String(role || '').trim().toLowerCase();
  if (!normalizedRole || !eventName) return;
  if (emitToRoleLocal(normalizedRole, eventName, payload)) return;
  void publishOperationalEvent({
    target: 'role',
    targetId: normalizedRole,
    eventName,
    payload,
  });
};

const emitNotificationCreated = (notification) => {
  const serialized = serializeNotification(notification);
  if (!serialized || !serialized.userId) return;
  emitToUser(serialized.userId, 'notification.created', serialized);
};

const emitOperationsChanged = (payload = {}) => {
  if (payload?.userId) {
    emitToUser(payload.userId, 'ops.changed', payload);
  }
  if (payload?.role) {
    emitToRole(payload.role, 'ops.changed', payload);
  }
  emitToRole('admin', 'ops.changed', payload);
};

const joinRouteRoom = (socket, routeId) => {
  if (!socket) return;
  withRoomKey(routeId, (roomKey) => socket.join(toRouteRoom(roomKey)));
};

const joinTripRoom = (socket, tripId) => {
  if (!socket) return;
  withRoomKey(tripId, (roomKey) => socket.join(toTripRoom(roomKey)));
};

const emitToRouteLocal = (routeId, eventName, payload) => {
  if (!ioInstance || !routeId || !eventName) return false;
  ioInstance.to(toRouteRoom(routeId)).emit(eventName, payload);
  return true;
};

const emitToRoute = (routeId, eventName, payload) => {
  if (!routeId || !eventName) return;
  if (emitToRouteLocal(routeId, eventName, payload)) return;
  void publishOperationalEvent({
    target: 'route',
    targetId: routeId,
    eventName,
    payload,
  });
};

const emitToTripLocal = (tripId, eventName, payload) => {
  if (!ioInstance || !tripId || !eventName) return false;
  ioInstance.to(toTripRoom(tripId)).emit(eventName, payload);
  return true;
};

const emitToTrip = (tripId, eventName, payload) => {
  if (!tripId || !eventName) return;
  if (emitToTripLocal(tripId, eventName, payload)) return;
  void publishOperationalEvent({
    target: 'trip',
    targetId: tripId,
    eventName,
    payload,
  });
};

const emitJeepneyLocationUpdate = ({
  tripId,
  routeId,
  jeepneyId,
  latitude,
  longitude,
  timestamp,
  speedMetersPerSecond,
  headingDegrees,
}) => {
  if (!ioInstance) return;

  const payload = {
    tripId: String(tripId || ''),
    routeId: String(routeId || ''),
    jeepneyId: String(jeepneyId || ''),
    latitude: Number(latitude),
    longitude: Number(longitude),
    timestamp: timestamp || new Date().toISOString(),
  };

  if (routeId) {
    emitToRoute(routeId, 'jeepney.location.updated', payload);
    routeLocationBatcher?.enqueue({
      ...payload,
      speedMetersPerSecond,
      headingDegrees,
    });
  }
};

const closeSocketServer = async () => {
  if (stopSecuritySubscriber) await stopSecuritySubscriber();
  stopSecuritySubscriber = null;
  routeLocationBatcher?.flushAll();
  routeLocationBatcher?.stop();
  routeLocationBatcher?.clear();
  routeLocationBatcher = null;

  const stopSubscriber = stopOperationalEventSubscriber;
  stopOperationalEventSubscriber = null;
  if (typeof stopSubscriber === 'function') {
    await stopSubscriber();
  }

  const io = ioInstance;
  ioInstance = null;
  if (!io) return;
  await new Promise((resolve) => io.close(() => resolve()));
};

module.exports = {
  attachSocketServer,
  closeSocketServer,
  emitNotificationCreated,
  emitOperationsChanged,
  emitJeepneyLocationUpdate,
  emitToRole,
  emitToUser,
  emitToRoute,
  emitToTrip,
  joinRouteRoom,
  joinTripRoom,
  maxCustomRoomsPerSocket,
  maxSubscriptionEventsPerWindow,
  getRouteLocationBatcher: () => routeLocationBatcher,
  getSocketServer: () => ioInstance,
};
