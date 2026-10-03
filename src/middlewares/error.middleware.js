const ApiError = require('../utils/apiError');

const notFound = (req, res, next) => {
  next(new ApiError(404, `Route not found: ${req.path}`));
};

const normalizeError = (error) => {
  if (error?.code === 11000) {
    const fieldName = Object.keys(error.keyPattern || error.keyValue || {})[0] || 'resource';
    return {
      status: 409,
      message: `${fieldName} already exists`,
      errors: [],
      code: 'DUPLICATE_RESOURCE',
      action: 'Refresh the list and choose a different value.',
    };
  }

  if (error?.name === 'ValidationError') {
    const errors = Object.values(error.errors || {}).map((item) => item.message);
    return {
      status: 400,
      message: errors[0] || 'Validation failed',
      errors,
      code: 'VALIDATION_FAILED',
      action: 'Review the highlighted fields and try again.',
    };
  }

  if (error?.name === 'CastError') {
    return {
      status: 400,
      message: `Invalid ${error.path || 'request value'}`,
      errors: [],
      code: 'INVALID_REQUEST_VALUE',
      action: 'Check the value and try again.',
    };
  }

  const status = error.statusCode || error.status || 500;
  const safe = Boolean(error?.isOperational || error instanceof ApiError);
  return {
    status,
    message: safe || status < 500
      ? (error.message || 'Request failed')
      : 'The server could not complete the request.',
    errors: error.errors || [],
    code: error.code || (status >= 500 ? 'SERVER_ERROR' : null),
    action: error.action || (status >= 500 ? 'Try again shortly. If the problem continues, contact support.' : null),
  };
};

const errorHandler = (err, _req, res, _next) => {
  const { status, message, errors, code, action } = normalizeError(err);
  if (err.retryAfter) res.set('Retry-After', String(err.retryAfter));
  return res.status(status).json({ success: false, message, errors, ...(code ? { code } : {}), ...(action ? { action } : {}) });
};

module.exports = { notFound, errorHandler };
