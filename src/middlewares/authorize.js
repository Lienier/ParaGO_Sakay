const ApiError = require('../utils/apiError');

const authorize =
  (...allowedRoles) =>
  (req, _res, next) => {
    if (!req.user) return next(new ApiError(401, 'Authentication required'));
    if (!allowedRoles.includes(req.user.role)) {
      return next(new ApiError(403, 'You are not authorized for this resource'));
    }
    return next();
  };

module.exports = authorize;
