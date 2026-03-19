const ok = (res, data = null, message = 'Success', status = 200) =>
  res.status(status).json({
    success: true,
    message,
    data,
  });

const fail = (res, message = 'Failed', errors = [], status = 400) =>
  res.status(status).json({
    success: false,
    message,
    errors,
  });

module.exports = { ok, fail };
