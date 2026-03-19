const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const { nodeEnv } = require('./config/env');
const authRoutes = require('./routes/auth.routes');
const userRoutes = require('./routes/users.routes');
const passengerRoutes = require('./routes/passengers.routes');
const driverRoutes = require('./routes/drivers.routes');
const adminRoutes = require('./routes/admin.routes');
const jeepneyRoutes = require('./routes/jeepneys.routes');
const routeRoutes = require('./routes/routes.routes');
const tripRoutes = require('./routes/trips.routes');
const pickupRequestRoutes = require('./routes/pickupRequests.routes');
const boardingRoutes = require('./routes/boarding.routes');
const rideSessionRoutes = require('./routes/rideSessions.routes');
const stopAlertRoutes = require('./routes/stopAlerts.routes');
const notificationRoutes = require('./routes/notifications.routes');
const reportRoutes = require('./routes/reports.routes');
const { notFound, errorHandler } = require('./middlewares/error.middleware');

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
app.use(cors());
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

app.use('/api/v1/auth', authLimiter, authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/passengers', passengerRoutes);
app.use('/api/v1/drivers', driverRoutes);
app.use('/api/v1/admin', adminRoutes);
app.use('/api/v1/jeepneys', jeepneyRoutes);
app.use('/api/v1/routes', routeRoutes);
app.use('/api/v1/trips', tripRoutes);
app.use('/api/v1/pickup-requests', pickupRequestRoutes);
app.use('/api/v1/boarding', boardingRoutes);
app.use('/api/v1/ride-sessions', rideSessionRoutes);
app.use('/api/v1/stop-alerts', stopAlertRoutes);
app.use('/api/v1/notifications', notificationRoutes);
app.use('/api/v1/reports', reportRoutes);

// Compatibility routes for clients that temporarily miss the /api/v1 prefix.
app.use('/auth', authLimiter, authRoutes);
app.use('/users', userRoutes);
app.use('/passengers', passengerRoutes);
app.use('/drivers', driverRoutes);
app.use('/admin', adminRoutes);
app.use('/jeepneys', jeepneyRoutes);
app.use('/routes', routeRoutes);
app.use('/trips', tripRoutes);
app.use('/pickup-requests', pickupRequestRoutes);
app.use('/boarding', boardingRoutes);
app.use('/ride-sessions', rideSessionRoutes);
app.use('/stop-alerts', stopAlertRoutes);
app.use('/notifications', notificationRoutes);
app.use('/reports', reportRoutes);

app.use(notFound);
app.use(errorHandler);

module.exports = app;
