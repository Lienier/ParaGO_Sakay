const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { jwtSecret, jwtExpiresIn, jwtRefreshSecret, jwtRefreshExpiresIn } = require('../config/env');

const signToken = (payload, type = 'access', expiresIn) => {
  const options = { algorithm: 'HS256', issuer: 'sakaygaray', audience: 'sakaygaray-api', jwtid: crypto.randomUUID() };
  const claims = { ...payload, purpose: type };
  if (type === 'refresh') {
    return jwt.sign(claims, jwtRefreshSecret, { ...options, ...(claims.exp ? {} : { expiresIn: expiresIn || jwtRefreshExpiresIn }) });
  }
  return jwt.sign(claims, jwtSecret, { ...options, expiresIn: '15m' });
};

const verify = (token, secret, purpose) => {
  const value = jwt.verify(token, secret, { algorithms: ['HS256'], issuer: 'sakaygaray', audience: 'sakaygaray-api' });
  if (value.purpose !== purpose || !value.jti || !value.sid) throw new Error('Invalid session token');
  return value;
};
const verifyAccessToken = (token) => verify(token, jwtSecret, 'access');
const verifyRefreshToken = (token) => verify(token, jwtRefreshSecret, 'refresh');

module.exports = {
  signToken,
  verifyAccessToken,
  verifyRefreshToken,
};
