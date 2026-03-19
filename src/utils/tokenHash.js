const crypto = require('crypto');

const tokenHash = (token) =>
  crypto.createHash('sha256').update(String(token || '')).digest('hex');

module.exports = tokenHash;
