const jwt = require('jsonwebtoken');
const { jwtSecret, jwtExpiresIn, jwtRefreshSecret, jwtRefreshExpiresIn } = require('../config/env');

const signToken = (payload, type = 'access') => {
  if (type === 'refresh') {
    return jwt.sign(payload, jwtRefreshSecret, { expiresIn: jwtRefreshExpiresIn });
  }
  return jwt.sign(payload, jwtSecret, { expiresIn: jwtExpiresIn });
};

const verifyAccessToken = (token) => jwt.verify(token, jwtSecret);
const verifyRefreshToken = (token) => jwt.verify(token, jwtRefreshSecret);

module.exports = {
  signToken,
  verifyAccessToken,
  verifyRefreshToken,
};
