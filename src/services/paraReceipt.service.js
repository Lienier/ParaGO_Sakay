const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../config/env');
const { requireSession } = require('./sessionSecurity.service');
const ApiError = require('../utils/apiError');
const signParaReceipt = ({ userId, sessionId, alertId }) => jwt.sign(
  { sub: String(userId), sid: sessionId, alertId, purpose: 'para-sound' }, jwtSecret,
  { algorithm: 'HS256', issuer: 'sakaygaray', audience: 'sakaygaray-para-sound', expiresIn: 60 });
const validateParaReceipt = async (receipt) => {
  let payload;
  try {
    payload = jwt.verify(receipt, jwtSecret, { algorithms: ['HS256'], issuer: 'sakaygaray', audience: 'sakaygaray-para-sound' });
    if (payload.purpose !== 'para-sound') throw new Error();
  } catch (_) { throw new ApiError(401, 'Alert authorization expired'); }
  const { user } = await requireSession(payload);
  if (user.role !== 'DRIVER') throw new ApiError(403, 'Forbidden');
  const alert = await require('../models/stopAlert').findById(payload.alertId);
  if (!alert || alert.status === 'dismissed') throw new ApiError(404, 'Alert unavailable');
  const { requireTrip, ensureDriverAssignedToTrip } = require('./routeContext.service');
  await ensureDriverAssignedToTrip(user, await requireTrip(alert.tripSessionId));
  return { alertId: payload.alertId, sessionId: payload.sid };
};
module.exports = { signParaReceipt, validateParaReceipt };
