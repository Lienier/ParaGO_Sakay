const AuthSession = require('../models/authSession');
const RefreshToken = require('../models/refreshToken');
const User = require('../models/user');
const ApiError = require('../utils/apiError');
const { redisKey, publishRedisEvent } = require('./redis.service');
const revocationChannel = redisKey('security', 'revocation');
const notifyRevocation = ({ userId, sessionId, reason }) =>
  publishRedisEvent(revocationChannel, { userId: String(userId), sessionId, reason });

const requireSession = async (payload, mongoSession = null) => {
  if (!payload.sid) throw new ApiError(401, 'Please sign in again');
  const active = await AuthSession.findOne({
    _id: payload.sid, userId: payload.sub,
  }).session(mongoSession);
  const user = await User.findOne({ _id: payload.sub, status: 'active' })
    .select('+authVersion').session(mongoSession);
  if (user && active?.revokedAt && active.revokedReason === 'replaced') {
    throw new ApiError(401, 'Your account was signed in on another device', [], 'SESSION_REPLACED');
  }
  if (!active || !user || active.revokedAt || active.expiresAt <= new Date() || active.authVersion !== (user.authVersion || 0)) throw new ApiError(401, 'Session is no longer active');
  return { active, user };
};

const revokeSessions = async ({ userId, sessionId, mongoSession = null }) => {
  if (!sessionId) await User.updateOne({ _id: userId }, { $inc: { authVersion: 1 } }, { session: mongoSession });
  const query = { userId, ...(sessionId ? { _id: sessionId } : {}) };
  await AuthSession.updateMany(query, { $set: { revokedAt: new Date() } }, { session: mongoSession });
  await RefreshToken.updateMany({ userId, ...(sessionId ? { sessionId } : {}), revokedAt: null },
    { $set: { revokedAt: new Date() } }, { session: mongoSession });
  if (!mongoSession) await notifyRevocation({ userId, sessionId });
};
module.exports = { requireSession, revokeSessions, notifyRevocation, revocationChannel };
