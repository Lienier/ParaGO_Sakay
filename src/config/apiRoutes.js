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
const reportRoutes = require('../routes/reports.routes');

const routeDefinitions = [
  { path: '/auth', router: authRoutes, useAuthLimiter: true },
  { path: '/users', router: userRoutes },
  { path: '/passengers', router: passengerRoutes },
  { path: '/drivers', router: driverRoutes },
  { path: '/admin', router: adminRoutes },
  { path: '/jeepneys', router: jeepneyRoutes },
  { path: '/routes', router: routeRoutes },
  { path: '/trips', router: tripRoutes },
  { path: '/pickup-requests', router: pickupRequestRoutes },
  { path: '/boarding', router: boardingRoutes },
  { path: '/ride-sessions', router: rideSessionRoutes },
  { path: '/stop-alerts', router: stopAlertRoutes },
  { path: '/support', router: supportRoutes },
  { path: '/notifications', router: notificationRoutes },
  { path: '/reports', router: reportRoutes },
];

const registerApiRoutes = (app, { prefix = '', authLimiter } = {}) => {
  for (const definition of routeDefinitions) {
    const middlewares = [];
    if (definition.useAuthLimiter && authLimiter) {
      middlewares.push(authLimiter);
    }
    middlewares.push(definition.router);
    app.use(`${prefix}${definition.path}`, ...middlewares);
  }
};

module.exports = {
  routeDefinitions,
  registerApiRoutes,
};
