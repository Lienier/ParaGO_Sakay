const normalizeAllowedOrigins = (origins = []) =>
  [...new Set((Array.isArray(origins) ? origins : [origins]).map((value) => String(value || '').trim()).filter(Boolean))];

const createCorsOriginDelegate = ({
  allowedOrigins = [],
  allowRequestsWithoutOrigin = true,
} = {}) => {
  const normalizedOrigins = normalizeAllowedOrigins(allowedOrigins);

  if (!normalizedOrigins.length) {
    return true;
  }

  return (origin, callback) => {
    if (!origin && allowRequestsWithoutOrigin) {
      callback(null, true);
      return;
    }

    if (normalizedOrigins.includes(origin)) {
      callback(null, true);
      return;
    }

    const error = new Error('Origin not allowed by CORS');
    error.statusCode = 403;
    callback(error);
  };
};

module.exports = {
  createCorsOriginDelegate,
  normalizeAllowedOrigins,
};
