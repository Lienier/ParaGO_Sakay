const multer = require('multer');
const ApiError = require('../utils/apiError');

const MAX_LICENSE_IMAGE_BYTES = 5 * 1024 * 1024;
const ACCEPTED_LICENSE_IMAGE_TYPES = new Set(['image/jpeg', 'image/png']);

const licenseImageFileFilter = (_req, file, callback) => {
  if (!ACCEPTED_LICENSE_IMAGE_TYPES.has(file.mimetype)) {
    callback(new ApiError(400, 'Driver license images must be JPEG or PNG files'));
    return;
  }
  callback(null, true);
};

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: MAX_LICENSE_IMAGE_BYTES,
    files: 2,
    fields: 20,
  },
  fileFilter: licenseImageFileFilter,
});

const runUpload = (middleware) => (req, res, next) => {
  middleware(req, res, (error) => {
    if (!error) return next();
    if (error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE') {
      return next(new ApiError(400, 'Each driver license image must be 5 MB or smaller'));
    }
    return next(error);
  });
};

const licensePairUpload = runUpload(
  upload.fields([
    { name: 'licenseFront', maxCount: 1 },
    { name: 'licenseBack', maxCount: 1 },
  ])
);

const singleLicenseUpload = runUpload(
  multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_LICENSE_IMAGE_BYTES, files: 1, fields: 2 },
    fileFilter: licenseImageFileFilter,
  }).single('licenseDocument')
);

module.exports = {
  ACCEPTED_LICENSE_IMAGE_TYPES,
  MAX_LICENSE_IMAGE_BYTES,
  licensePairUpload,
  singleLicenseUpload,
};
