const ApiError = require('./apiError');

const CP_NUMBER_PATTERN = /^09\d{9}$/;

const normalizeLicenseNumber = (value) =>
  String(value ?? '')
    .trim()
    .replace(/\s+/g, ' ')
    .toUpperCase();

const normalizeCpNumber = (value) => String(value ?? '').trim();

const validateCpNumber = (value, { required = true } = {}) => {
  const normalized = normalizeCpNumber(value);
  if (!normalized && !required) return normalized;
  if (!normalized) throw new ApiError(400, 'CP number is required');
  if (!CP_NUMBER_PATTERN.test(normalized)) {
    throw new ApiError(400, 'CP number must contain exactly 11 digits and start with 09');
  }
  return normalized;
};

const validateLicenseNumber = (value, { required = true } = {}) => {
  const normalized = normalizeLicenseNumber(value);
  if (!normalized && !required) return normalized;
  if (!normalized) throw new ApiError(400, 'License number is required');
  return normalized;
};

module.exports = {
  CP_NUMBER_PATTERN,
  normalizeCpNumber,
  normalizeLicenseNumber,
  validateCpNumber,
  validateLicenseNumber,
};
