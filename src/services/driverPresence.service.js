const Jeepney = require('../models/jeepney');
const TripSession = require('../models/tripSession');

const DRIVER_PRESENCE_TIMEOUT_MS = 5 * 60 * 1000;

const normalizeStatus = (value) => String(value || '').trim().toLowerCase();

const asDate = (value) => {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const resolveDriverLastSeen = async (driver) => {
  const assignedLastSeenAt = asDate(driver?.assignedJeepneyId?.lastSeenAt);
  if (assignedLastSeenAt) {
    return {
      lastSeenAt: assignedLastSeenAt,
      presenceSource: 'assigned_jeepney',
    };
  }

  if (!driver?._id) {
    return { lastSeenAt: null, presenceSource: null };
  }

  const linkedJeepney = await Jeepney.findOne({
    currentDriverId: driver._id,
    lastSeenAt: { $exists: true },
  })
    .select('lastSeenAt')
    .sort({ lastSeenAt: -1, updatedAt: -1, createdAt: -1 });
  const linkedLastSeenAt = asDate(linkedJeepney?.lastSeenAt);
  if (linkedLastSeenAt) {
    return {
      lastSeenAt: linkedLastSeenAt,
      presenceSource: 'current_jeepney',
    };
  }

  const activeTrip = await TripSession.findOne({
    driverId: driver._id,
    status: { $in: ['active', 'scheduled'] },
  })
    .populate('jeepneyId', 'lastSeenAt')
    .select('jeepneyId')
    .sort({ updatedAt: -1, createdAt: -1 });
  const tripLastSeenAt = asDate(activeTrip?.jeepneyId?.lastSeenAt);
  if (tripLastSeenAt) {
    return {
      lastSeenAt: tripLastSeenAt,
      presenceSource: 'trip_jeepney',
    };
  }

  return { lastSeenAt: null, presenceSource: null };
};

const deriveDriverPresence = async (driver, { now = new Date() } = {}) => {
  const accountStatus = normalizeStatus(driver?.userId?.status);
  const driverStatus = normalizeStatus(driver?.status);
  const { lastSeenAt, presenceSource } = await resolveDriverLastSeen(driver);
  const lastSeenMillis = lastSeenAt?.getTime();
  const isFresh =
    lastSeenMillis != null && now.getTime() - lastSeenMillis <= DRIVER_PRESENCE_TIMEOUT_MS;

  const isOnline =
    accountStatus === 'active' && driverStatus === 'active' && Boolean(isFresh);

  return {
    accountStatus: accountStatus || 'unknown',
    presenceStatus: isOnline ? 'online' : 'offline',
    isOnline,
    lastSeenAt: lastSeenAt ? lastSeenAt.toISOString() : null,
    presenceSource,
    presenceTimeoutMs: DRIVER_PRESENCE_TIMEOUT_MS,
  };
};

module.exports = {
  DRIVER_PRESENCE_TIMEOUT_MS,
  deriveDriverPresence,
};
