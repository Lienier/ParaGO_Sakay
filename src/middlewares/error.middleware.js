const ApiError = require('../utils/apiError');

const notFound = (req, res, next) => {
  next(new ApiError(404, `Route not found: ${req.originalUrl}`));
};

const normalizeError = (error) => {
  if (error?.code === 11000) {
    const fieldName = Object.keys(error.keyPattern || error.keyValue || {})[0] || 'resource';
    return {
      status: 409,
      message: `${fieldName} already exists`,
      errors: [],
    };
  }

  if (error?.name === 'ValidationError') {
    const errors = Object.values(error.errors || {}).map((item) => item.message);
    return {
      status: 400,
      message: errors[0] || 'Validation failed',
      errors,
    };
  }

  if (error?.name === 'CastError') {
    return {
      status: 400,
      message: `Invalid ${error.path || 'request value'}`,
      errors: [],
    };
  }

  return {
    status: error.statusCode || 500,
    message: error.message || 'Internal Server Error',
    errors: error.errors || [],
  };
};

const errorHandler = (err, _req, res, _next) => {
  const { status, message, errors } = normalizeError(err);
  return res.status(status).json({ success: false, message, errors });
};

module.exports = { notFound, errorHandler };
