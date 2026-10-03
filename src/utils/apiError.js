class ApiError extends Error {
  constructor(statusCode, message = 'Request failed', errors = [], code = null, action = null) {
    super(message);
    this.statusCode = statusCode;
    this.errors = errors;
    this.code = code;
    this.action = action;
    this.isOperational = true;
    Error.captureStackTrace(this, this.constructor);
  }
}

module.exports = ApiError;
