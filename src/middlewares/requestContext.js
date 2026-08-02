const crypto = require('crypto');
const morgan = require('morgan');

const requestIdPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{7,127}$/;

const requestContext = (req, res, next) => {
  const supplied = String(req.get('x-request-id') || '').trim();
  req.id = requestIdPattern.test(supplied) ? supplied : crypto.randomUUID();
  res.setHeader('X-Request-Id', req.id);
  next();
};

const createStructuredHttpLogger = (options = {}) =>
  morgan((tokens, req, res) => {
    const duration = Number(tokens['response-time'](req, res));
    return JSON.stringify({
      type: 'http.request',
      requestId: req.id,
      method: req.method,
      path: String(req.originalUrl || req.path || '').split('?')[0],
      status: Number(tokens.status(req, res)),
      durationMs: Number.isFinite(duration) ? duration : null,
      occurredAt: new Date().toISOString(),
    });
  }, options);

const structuredHttpLogger = createStructuredHttpLogger();

module.exports = {
  requestContext,
  structuredHttpLogger,
  createStructuredHttpLogger,
  requestIdPattern,
};
