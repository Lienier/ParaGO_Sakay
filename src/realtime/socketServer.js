const { Server } = require('socket.io');

const User = require('../models/user');
const { verifyAccessToken } = require('../utils/jwt');
const { createCorsOriginDelegate } = require('../utils/cors');

let ioInstance = null;

const normalizeRoomKey = (value) => String(value || '').trim();
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

  const queryToken = socket.handshake.query?.token;
  if (typeof queryToken === 'string' && queryToken.trim()) {
    return queryToken.trim();
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

  io.use(async (socket, next) => {
    const token = extractToken(socket);
    if (!token) {
      next(new Error('Authentication token missing'));
      return;
    }

    try {
      const payload = verifyAccessToken(token);
      const user = await User.findById(payload.sub).select('-passwordHash');
      if (!user || user.status !== 'active') {
        next(new Error('Invalid user session'));
        return;
      }
      socket.data.user = {
        id: user._id.toString(),
        fullName: user.fullName,
        role: user.role,
      };
      next();
    } catch (_error) {
      next(new Error('Invalid or expired token'));
    }
  });

  io.on('connection', (socket) => {
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

    // Allow clients to subscribe to route/trip updates
    socket.on('subscribe.route', (routeId) => {
      withRoomKey(routeId, (roomKey) => socket.join(toRouteRoom(roomKey)));
    });

    socket.on('subscribe.trip', (tripId) => {
      withRoomKey(tripId, (roomKey) => socket.join(toTripRoom(roomKey)));
    });

    socket.on('unsubscribe.route', (routeId) => {
      withRoomKey(routeId, (roomKey) => socket.leave(toRouteRoom(roomKey)));
    });

    socket.on('unsubscribe.trip', (tripId) => {
      withRoomKey(tripId, (roomKey) => socket.leave(toTripRoom(roomKey)));
    });
  });

  ioInstance = io;
  return io;
};

const emitToUser = (userId, eventName, payload) => {
  if (!ioInstance || !userId || !eventName) return;
  ioInstance.to(toUserRoom(userId)).emit(eventName, payload);
};

const emitToRole = (role, eventName, payload) => {
  const normalizedRole = String(role || '').trim().toLowerCase();
  if (!ioInstance || !normalizedRole || !eventName) return;
  ioInstance.to(toRoleRoom(normalizedRole)).emit(eventName, payload);
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

const emitToRoute = (routeId, eventName, payload) => {
  if (!ioInstance || !routeId || !eventName) return;
  ioInstance.to(toRouteRoom(routeId)).emit(eventName, payload);
};

const emitToTrip = (tripId, eventName, payload) => {
  if (!ioInstance || !tripId || !eventName) return;
  ioInstance.to(toTripRoom(tripId)).emit(eventName, payload);
};

const emitJeepneyLocationUpdate = ({
  tripId,
  routeId,
  jeepneyId,
  latitude,
  longitude,
  timestamp,
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

  // Broadcast to all passengers watching this route
  if (routeId) {
    emitToRoute(routeId, 'jeepney.location.updated', payload);
  }

  // Broadcast to all passengers/drivers on this specific trip
  if (tripId) {
    emitToTrip(tripId, 'jeepney.location.updated', payload);
  }

  // Broadcast to all passengers (for active trips view)
  emitToRole('passenger', 'jeepney.location.updated', payload);
};

module.exports = {
  attachSocketServer,
  emitNotificationCreated,
  emitOperationsChanged,
  emitJeepneyLocationUpdate,
  emitToRole,
  emitToUser,
  emitToRoute,
  emitToTrip,
  joinRouteRoom,
  joinTripRoom,
  getSocketServer: () => ioInstance,
};
