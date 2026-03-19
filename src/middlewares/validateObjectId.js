const mongoose = require('mongoose');
const ApiError = require('../utils/apiError');

const validateObjectId = (paramName = 'id') => (req, _res, next) => {
  const value = req.params[paramName];
  if (!value || !mongoose.Types.ObjectId.isValid(value)) {
    return next(new ApiError(400, `Invalid parameter: ${paramName}`));
  }
  return next();
};

module.exports = validateObjectId;
