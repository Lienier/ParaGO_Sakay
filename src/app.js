const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const mongoose = require('mongoose');

const { corsAllowedOrigins } = require('./config/env');
const { registerApiRoutes } = require('./config/apiRoutes');
const { notFound, errorHandler } = require('./middlewares/error.middleware');
const { createCorsOriginDelegate } = require('./utils/cors');
const { getRedisHealth } = require('./services/redis.service');
const {
  requestContext,
  structuredHttpLogger,
} = require('./middlewares/requestContext');
const { apiRateLimiters } = require('./middlewares/rateLimits');

const app = express();
app.set('trust proxy', 1);
app.disable('x-powered-by');

const apiRootInfo = (_req, res) => {
  res.status(200).json({
    success: true,
    message: 'ParaGO API is running',
    docs: 'Available routes are under /api/v1',
    service: 'ParaGO Backend',
  });
};

app.use(
  helmet({
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: 'same-site' },
  })
);
app.use(requestContext);
app.use(structuredHttpLogger);
app.use(
  cors({
    origin: createCorsOriginDelegate({
      allowedOrigins: corsAllowedOrigins.length ? [...corsAllowedOrigins, 'https://downloads.sakaygaray.com'] : [],
    }),
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type', 'X-Request-Id', 'X-App-Build'],
    exposedHeaders: ['X-Request-Id', 'RateLimit', 'RateLimit-Policy', 'Retry-After'],
    maxAge: 600,
  })
);
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));

app.get('/reset-password', require('./routes/passwordResetPage'));
app.get('/', apiRootInfo);
app.get('/api', apiRootInfo);
app.get('/api/v1', apiRootInfo);
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: 'ParaGO Backend' });
});
app.get('/api/v1/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: 'ParaGO Backend' });
});
const readiness = (_req, res) => {
  const mongoReady = mongoose.connection.readyState === 1;
  const redis = getRedisHealth();
  const ready = mongoReady && (!redis.configured || redis.ready);
  res.status(ready ? 200 : 503).json({
    status: ready ? 'ready' : 'not_ready',
    dependencies: {
      mongodb: mongoReady ? 'healthy' : 'unhealthy',
      redis: redis.status,
    },
  });
};
app.get('/ready', readiness);
app.get('/api/v1/ready', readiness);

registerApiRoutes(app, { prefix: '/api/v1', rateLimiters: apiRateLimiters });

// Compatibility routes for clients that temporarily miss the /api/v1 prefix.
registerApiRoutes(app, { rateLimiters: apiRateLimiters });

app.use(notFound);
app.use(errorHandler);

module.exports = app;
