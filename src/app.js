const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const { nodeEnv, corsAllowedOrigins } = require('./config/env');
const { registerApiRoutes } = require('./config/apiRoutes');
const { notFound, errorHandler } = require('./middlewares/error.middleware');
const { createCorsOriginDelegate } = require('./utils/cors');

const app = express();

const apiRootInfo = (_req, res) => {
  res.status(200).json({
    success: true,
    message: 'ParaGO API is running',
    docs: 'Available routes are under /api/v1',
    service: 'ParaGO Backend',
  });
};

app.use(helmet());
app.use(
  cors({
    origin: createCorsOriginDelegate({
      allowedOrigins: corsAllowedOrigins,
    }),
  })
);
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false }));
app.use(
  morgan(nodeEnv === 'development' ? 'dev' : 'combined')
);

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api', limiter);

const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many authentication requests. Please try again in a minute.',
  },
});

app.get('/', apiRootInfo);
app.get('/api', apiRootInfo);
app.get('/api/v1', apiRootInfo);
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: 'ParaGO Backend' });
});
app.get('/api/v1/health', (_req, res) => {
  res.status(200).json({ status: 'ok', service: 'ParaGO Backend' });
});

registerApiRoutes(app, { prefix: '/api/v1', authLimiter });

// Compatibility routes for clients that temporarily miss the /api/v1 prefix.
registerApiRoutes(app, { authLimiter });

app.use(notFound);
app.use(errorHandler);

module.exports = app;
