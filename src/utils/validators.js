const mongoose = require('mongoose');
const ApiError = require('./apiError');

const ensureObjectId = (value, fieldName) => {
  if (!mongoose.Types.ObjectId.isValid(String(value || ''))) {
    throw new ApiError(400, `Invalid ${fieldName}`);
  }
};

const ensureEnum = (value, fieldName, allowed) => {
  if (!allowed.includes(value)) {
    throw new ApiError(400, `${fieldName} must be one of: ${allowed.join(', ')}`);
  }
};

const ensureLatLng = (lat, lng, fieldPrefix = 'location') => {
  if (lat == null && lng == null) return;
  const latNum = Number(lat);
  const lngNum = Number(lng);
  if (!Number.isFinite(latNum) || latNum < -90 || latNum > 90) {
    throw new ApiError(400, `Invalid ${fieldPrefix}.lat`);
  }
  if (!Number.isFinite(lngNum) || lngNum < -180 || lngNum > 180) {
    throw new ApiError(400, `Invalid ${fieldPrefix}.lng`);
  }
};

module.exports = {
  ensureObjectId,
  ensureEnum,
  ensureLatLng,
};
