const Announcement = require('../models/announcement');
const AnnouncementDismissal = require('../models/announcementDismissal');
const ApiError = require('../utils/apiError');
const { emitToRole } = require('../realtime/socketServer');

const ANNOUNCEMENT_CATEGORIES = [
  'service_change',
  'disruption',
  'maintenance',
  'safety',
  'general',
];
const ANNOUNCEMENT_SEVERITIES = ['info', 'warning', 'critical'];
const ANNOUNCEMENT_AUDIENCES = ['PASSENGER', 'DRIVER'];
const ANNOUNCEMENT_STATUSES = [
  'scheduled',
  'published',
  'expired',
  'archived',
];
const DEFAULT_ADMIN_PAGE_SIZE = 25;
const MAX_ADMIN_PAGE_SIZE = 50;
const ISO_TIMESTAMP_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|([+-])(\d{2}):(\d{2}))$/;

const isValidIsoTimestamp = (value) => {
  const match = typeof value === 'string'
    ? value.match(ISO_TIMESTAMP_PATTERN)
    : null;
  if (!match) return false;
  const [, year, month, day, hour, minute, second, , offsetHour, offsetMinute] =
    match;
  const yearNumber = Number(year);
  const monthNumber = Number(month);
  const dayNumber = Number(day);
  const daysInMonth =
    monthNumber >= 1 && monthNumber <= 12
      ? new Date(Date.UTC(yearNumber, monthNumber, 0)).getUTCDate()
      : 0;
  return (
    dayNumber >= 1 &&
    dayNumber <= daysInMonth &&
    Number(hour) <= 23 &&
    Number(minute) <= 59 &&
    Number(second) <= 59 &&
    (offsetHour == null ||
      (Number(offsetHour) <= 14 && Number(offsetMinute) <= 59))
  );
};

const parseDate = (value, fieldName, { optional = false } = {}) => {
  if ((value == null || value === '') && optional) return null;
  if (
    !(value instanceof Date) &&
    !isValidIsoTimestamp(value)
  ) {
    throw new ApiError(400, `${fieldName} must be a valid ISO timestamp`);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new ApiError(400, `${fieldName} must be a valid ISO timestamp`);
  }
  return date;
};

const parsePositiveInteger = (value, fieldName, fallback, maximum = null) => {
  if (value == null || value === '') return fallback;
  const text = String(value).trim();
  if (!/^\d+$/.test(text)) {
    throw new ApiError(400, `${fieldName} must be a positive integer`);
  }
  const parsed = Number(text);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new ApiError(400, `${fieldName} must be a positive integer`);
  }
  return maximum == null ? parsed : Math.min(parsed, maximum);
};

const requireText = (value, fieldName, maxLength) => {
  const text = String(value || '').trim();
  if (!text) throw new ApiError(400, `${fieldName} is required`);
  if (text.length > maxLength) {
    throw new ApiError(400, `${fieldName} must not exceed ${maxLength} characters`);
  }
  return text;
};

const normalizeEnum = (value, fieldName, allowed) => {
  const normalized = String(value || '').trim().toLowerCase();
  if (!allowed.includes(normalized)) {
    throw new ApiError(400, `${fieldName} must be one of: ${allowed.join(', ')}`);
  }
  return normalized;
};

const normalizeAudiences = (value) => {
  if (!Array.isArray(value)) {
    throw new ApiError(400, 'audiences must be an array');
  }
  const audiences = [
    ...new Set(value.map((item) => String(item || '').trim().toUpperCase())),
  ];
  if (
    audiences.length === 0 ||
    audiences.some((audience) => !ANNOUNCEMENT_AUDIENCES.includes(audience))
  ) {
    throw new ApiError(
      400,
      'audiences must contain PASSENGER, DRIVER, or both'
    );
  }
  return audiences;
};

const statusForTiming = ({ startsAt, expiresAt, now = new Date() }) => {
  if (expiresAt && expiresAt <= now) return 'expired';
  return startsAt > now ? 'scheduled' : 'published';
};

const validateTiming = (startsAt, expiresAt) => {
  if (expiresAt && expiresAt <= startsAt) {
    throw new ApiError(400, 'expiresAt must be later than startsAt');
  }
};

const serializeUser = (value) => {
  if (!value) return null;
  if (typeof value === 'object' && value._id) {
    return {
      id: String(value._id),
      fullName: String(value.fullName || ''),
    };
  }
  return { id: String(value), fullName: '' };
};

const serializeAnnouncement = (value) => {
  const raw = typeof value?.toObject === 'function' ? value.toObject() : value;
  if (!raw) return null;
  const iso = (date) => (date ? new Date(date).toISOString() : null);
  return {
    id: String(raw._id || raw.id || ''),
    title: String(raw.title || ''),
    body: String(raw.body || ''),
    category: String(raw.category || ''),
    severity: String(raw.severity || ''),
    audiences: Array.isArray(raw.audiences) ? raw.audiences : [],
    status: String(raw.status || ''),
    revision: Number(raw.revision || 1),
    startsAt: iso(raw.startsAt),
    expiresAt: iso(raw.expiresAt),
    publishedAt: iso(raw.publishedAt),
    archivedAt: iso(raw.archivedAt),
    createdAt: iso(raw.createdAt),
    updatedAt: iso(raw.updatedAt),
    creator: serializeUser(raw.createdByAdminId),
    lastEditor: serializeUser(raw.updatedByAdminId),
    archivedBy: serializeUser(raw.archivedByAdminId),
  };
};

const populateAudit = (query) =>
  query
    .populate('createdByAdminId', 'fullName')
    .populate('updatedByAdminId', 'fullName')
    .populate('archivedByAdminId', 'fullName');

const emitAnnouncement = (eventName, announcement, audiences) => {
  const payload = serializeAnnouncement(announcement);
  for (const audience of new Set(audiences || [])) {
    emitToRole(audience, eventName, payload);
  }
};

const buildPayload = (input, existing = null) => {
  const startsAt = parseDate(
    input.startsAt ?? existing?.startsAt ?? new Date(),
    'startsAt'
  );
  const expiresAt = parseDate(
    Object.prototype.hasOwnProperty.call(input, 'expiresAt')
      ? input.expiresAt
      : existing?.expiresAt,
    'expiresAt',
    { optional: true }
  );
  validateTiming(startsAt, expiresAt);
  return {
    title: requireText(input.title ?? existing?.title, 'title', 160),
    body: requireText(input.body ?? existing?.body, 'body', 5000),
    category: normalizeEnum(
      input.category ?? existing?.category,
      'category',
      ANNOUNCEMENT_CATEGORIES
    ),
    severity: normalizeEnum(
      input.severity ?? existing?.severity,
      'severity',
      ANNOUNCEMENT_SEVERITIES
    ),
    audiences: normalizeAudiences(input.audiences ?? existing?.audiences),
    startsAt,
    expiresAt,
  };
};

const listActiveAnnouncements = async ({ user }) => {
  const now = new Date();
  const announcements = await populateAudit(
    Announcement.find({
      status: { $ne: 'archived' },
      audiences: user.role,
      startsAt: { $lte: now },
      $or: [{ expiresAt: null }, { expiresAt: { $gt: now } }],
    }).sort({ startsAt: -1, createdAt: -1 })
  );
  if (announcements.length === 0) return [];

  const dismissals = await AnnouncementDismissal.find({
    userId: user._id,
    announcementId: { $in: announcements.map((item) => item._id) },
  }).select('announcementId revision');
  const dismissed = new Set(
    dismissals.map((item) => `${item.announcementId}:${item.revision}`)
  );
  return announcements
    .filter((item) => !dismissed.has(`${item._id}:${item.revision}`))
    .map(serializeAnnouncement);
};

const dismissAnnouncement = async ({ user, announcementId, revision }) => {
  const requestedRevision = parsePositiveInteger(
    revision,
    'revision',
    null
  );
  if (requestedRevision == null) {
    throw new ApiError(400, 'revision is required');
  }
  const now = new Date();
  const announcement = await Announcement.findOne({
    _id: announcementId,
    status: { $ne: 'archived' },
    audiences: user.role,
    startsAt: { $lte: now },
    $or: [{ expiresAt: null }, { expiresAt: { $gt: now } }],
  });
  if (!announcement) throw new ApiError(404, 'Active announcement not found');
  if (announcement.revision !== requestedRevision) {
    throw new ApiError(
      409,
      'Announcement revision changed',
      [{ currentRevision: announcement.revision }]
    );
  }
  await AnnouncementDismissal.findOneAndUpdate(
    {
      announcementId: announcement._id,
      userId: user._id,
      revision: requestedRevision,
    },
    { $set: { dismissedAt: now } },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );
  return {
    announcementId: String(announcement._id),
    revision: requestedRevision,
    dismissedAt: now.toISOString(),
  };
};

const listAdminAnnouncements = async ({ filters = {} }) => {
  const page = parsePositiveInteger(filters.page, 'page', 1);
  const limit = parsePositiveInteger(
    filters.limit,
    'limit',
    DEFAULT_ADMIN_PAGE_SIZE,
    MAX_ADMIN_PAGE_SIZE
  );
  const query = {};
  if (filters.status) {
    query.status = normalizeEnum(
      filters.status,
      'status',
      ANNOUNCEMENT_STATUSES
    );
  }
  if (filters.category) {
    query.category = normalizeEnum(
      filters.category,
      'category',
      ANNOUNCEMENT_CATEGORIES
    );
  }
  if (filters.severity) {
    query.severity = normalizeEnum(
      filters.severity,
      'severity',
      ANNOUNCEMENT_SEVERITIES
    );
  }
  if (filters.audience) {
    const audience = String(filters.audience).trim().toUpperCase();
    if (!ANNOUNCEMENT_AUDIENCES.includes(audience)) {
      throw new ApiError(
        400,
        `audience must be one of: ${ANNOUNCEMENT_AUDIENCES.join(', ')}`
      );
    }
    query.audiences = audience;
  }
  if (filters.from || filters.to) {
    query.startsAt = {};
    if (filters.from) query.startsAt.$gte = parseDate(filters.from, 'from');
    if (filters.to) query.startsAt.$lte = parseDate(filters.to, 'to');
    if (
      query.startsAt.$gte &&
      query.startsAt.$lte &&
      query.startsAt.$gte > query.startsAt.$lte
    ) {
      throw new ApiError(400, 'from must be earlier than or equal to to');
    }
  }
  const [list, total] = await Promise.all([
    populateAudit(
      Announcement.find(query)
        .sort({ startsAt: -1, createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit)
    ),
    Announcement.countDocuments(query),
  ]);
  return {
    items: list.map(serializeAnnouncement),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
};

const createAnnouncement = async ({ admin, input }) => {
  const payload = buildPayload(input);
  const now = new Date();
  const status = statusForTiming({ ...payload, now });
  if (status === 'expired') {
    throw new ApiError(400, 'An announcement cannot be created already expired');
  }
  if (payload.severity === 'critical' && input.confirmCritical !== true) {
    throw new ApiError(
      400,
      'confirmCritical must be true for critical announcements'
    );
  }
  let announcement = await Announcement.create({
    ...payload,
    status,
    publishedAt: status === 'published' ? now : null,
    createdByAdminId: admin._id,
    updatedByAdminId: admin._id,
  });
  announcement = await populateAudit(Announcement.findById(announcement._id));
  if (status === 'published') {
    emitAnnouncement('announcement.published', announcement, payload.audiences);
  }
  return serializeAnnouncement(announcement);
};

const updateAnnouncement = async ({ admin, announcementId, input }) => {
  const announcement = await Announcement.findById(announcementId);
  if (!announcement) throw new ApiError(404, 'Announcement not found');
  if (['expired', 'archived'].includes(announcement.status)) {
    throw new ApiError(
      409,
      `${announcement.status === 'expired' ? 'Expired' : 'Archived'} announcements cannot be edited`
    );
  }
  const previousAudiences = [...announcement.audiences];
  const previousStatus = announcement.status;
  const payload = buildPayload(input, announcement);
  const now = new Date();
  const status = statusForTiming({ ...payload, now });
  if (status === 'expired') {
    throw new ApiError(400, 'An announcement cannot be updated already expired');
  }
  if (payload.severity === 'critical' && input.confirmCritical !== true) {
    throw new ApiError(
      400,
      'confirmCritical must be true for critical announcements'
    );
  }
  Object.assign(announcement, payload, {
    status,
    revision: announcement.revision + 1,
    updatedByAdminId: admin._id,
    publishedAt:
      status === 'published' ? announcement.publishedAt || now : null,
  });
  await announcement.save();
  const populated = await populateAudit(Announcement.findById(announcement._id));
  const audiences = [...new Set([...previousAudiences, ...payload.audiences])];
  const eventName =
    status === 'published' && previousStatus !== 'published'
      ? 'announcement.published'
      : 'announcement.updated';
  emitAnnouncement(eventName, populated, audiences);
  return serializeAnnouncement(populated);
};

const archiveAnnouncement = async ({
  admin,
  announcementId,
  confirmActiveArchive = false,
}) => {
  const announcement = await Announcement.findById(announcementId);
  if (!announcement) throw new ApiError(404, 'Announcement not found');
  if (announcement.status === 'archived') {
    return serializeAnnouncement(
      await populateAudit(Announcement.findById(announcementId))
    );
  }
  const now = new Date();
  const isActive =
    announcement.startsAt <= now &&
    (!announcement.expiresAt || announcement.expiresAt > now);
  if (isActive && confirmActiveArchive !== true) {
    throw new ApiError(
      400,
      'confirmActiveArchive must be true for active announcements'
    );
  }
  const audiences = [...announcement.audiences];
  announcement.status = 'archived';
  announcement.archivedAt = now;
  announcement.archivedByAdminId = admin._id;
  announcement.updatedByAdminId = admin._id;
  await announcement.save();
  const populated = await populateAudit(Announcement.findById(announcement._id));
  emitAnnouncement('announcement.archived', populated, audiences);
  return serializeAnnouncement(populated);
};

const reconcileAnnouncementStatuses = async () => {
  const now = new Date();
  let expired = 0;
  let published = 0;

  while (true) {
    const announcement = await Announcement.findOneAndUpdate(
      {
        status: { $in: ['scheduled', 'published'] },
        expiresAt: { $ne: null, $lte: now },
      },
      { $set: { status: 'expired' } },
      { new: true, sort: { expiresAt: 1 } }
    );
    if (!announcement) break;
    expired += 1;
    emitAnnouncement(
      'announcement.updated',
      announcement,
      announcement.audiences
    );
  }

  while (true) {
    const announcement = await Announcement.findOneAndUpdate(
      {
        status: 'scheduled',
        startsAt: { $lte: now },
        $or: [{ expiresAt: null }, { expiresAt: { $gt: now } }],
      },
      { $set: { status: 'published', publishedAt: now } },
      { new: true, sort: { startsAt: 1 } }
    );
    if (!announcement) break;
    published += 1;
    emitAnnouncement(
      'announcement.published',
      announcement,
      announcement.audiences
    );
  }
  return { published, expired };
};

module.exports = {
  ANNOUNCEMENT_CATEGORIES,
  ANNOUNCEMENT_SEVERITIES,
  ANNOUNCEMENT_AUDIENCES,
  ANNOUNCEMENT_STATUSES,
  DEFAULT_ADMIN_PAGE_SIZE,
  MAX_ADMIN_PAGE_SIZE,
  normalizeAudiences,
  statusForTiming,
  buildPayload,
  serializeAnnouncement,
  listActiveAnnouncements,
  dismissAnnouncement,
  listAdminAnnouncements,
  createAnnouncement,
  updateAnnouncement,
  archiveAnnouncement,
  reconcileAnnouncementStatuses,
};
