const authRoutes = require('../routes/auth.routes');
const userRoutes = require('../routes/users.routes');
const passengerRoutes = require('../routes/passengers.routes');
const driverRoutes = require('../routes/drivers.routes');
const adminRoutes = require('../routes/admin.routes');
const jeepneyRoutes = require('../routes/jeepneys.routes');
const routeRoutes = require('../routes/routes.routes');
const tripRoutes = require('../routes/trips.routes');
const pickupRequestRoutes = require('../routes/pickupRequests.routes');
const boardingRoutes = require('../routes/boarding.routes');
const rideSessionRoutes = require('../routes/rideSessions.routes');
const stopAlertRoutes = require('../routes/stopAlerts.routes');
const supportRoutes = require('../routes/support.routes');
const notificationRoutes = require('../routes/notifications.routes');
const announcementRoutes = require('../routes/announcements.routes');
const reportRoutes = require('../routes/reports.routes');
const operationsRoutes = require('../routes/operations.routes');

const routeDefinitions = [
  { path: '/auth', router: authRoutes, rateLimitGroup: 'auth' },
  { path: '/users', router: userRoutes },
  { path: '/passengers', router: passengerRoutes },
  { path: '/drivers', router: driverRoutes },
  { path: '/admin', router: adminRoutes, rateLimitGroup: 'admin' },
  { path: '/jeepneys', router: jeepneyRoutes },
  { path: '/routes', router: routeRoutes },
  { path: '/trips', router: tripRoutes },
  { path: '/pickup-requests', router: pickupRequestRoutes },
  { path: '/boarding', router: boardingRoutes },
  { path: '/ride-sessions', router: rideSessionRoutes },
  { path: '/stop-alerts', router: stopAlertRoutes },
  { path: '/support', router: supportRoutes, rateLimitGroup: 'support' },
  { path: '/notifications', router: notificationRoutes },
  { path: '/announcements', router: announcementRoutes },
  { path: '/reports', router: reportRoutes, rateLimitGroup: 'admin' },
  { path: '/operations', router: operationsRoutes, rateLimitGroup: 'admin' },
];

const registerApiRoutes = (app, { prefix = '', rateLimiters = {} } = {}) => {
  for (const definition of routeDefinitions) {
    const middlewares = [];
    const limiter =
      rateLimiters[definition.rateLimitGroup || 'general'] ||
      rateLimiters.general;
    if (limiter) {
      middlewares.push(definition.path === '/auth'
        ? (req, res, next) => {
          if (['/me', '/logout', '/refresh'].includes(req.path)) {
            return (rateLimiters.session || limiter)(req, res, next);
          }
          if (rateLimiters.authIp) return rateLimiters.authIp(req, res, (error) => error ? next(error) : limiter(req, res, next));
          return limiter(req, res, next);
        }
        : limiter);
    }
    middlewares.push(definition.router);
    app.use(`${prefix}${definition.path}`, ...middlewares);
  }
};

module.exports = {
  routeDefinitions,
  registerApiRoutes,
};
