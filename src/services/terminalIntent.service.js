const Driver = require('../models/driver');
const User = require('../models/user');
const Jeepney = require('../models/jeepney');
const Route = require('../models/route');
const Trip = require('../models/tripSession');
const { driverError, DRIVER_ERROR_CODES } = require('../utils/driverError');
const queue = require('./terminalQueue.service');
const { resolveRouteTerminalStop } = require('./hybridDispatch.service');

async function createTerminalIntent({ driverId, routeId, jeepneyId, assignedRouteOnly = false, selectRoute = false }) {
  return queue.transaction(routeId, async session => {
    // Lock the driver and vehicle as well as the route. Different-route requests
    // must not create a competing intent or race with arrival profile updates.
    const driver = await Driver.findOneAndUpdate({ _id: driverId },
      { $set: { updatedAt: new Date() } }, { new: true, session });
    if (!driver) throw driverError(404, 'DRIVER_NOT_FOUND', 'The driver record could not be found.', 'Refresh the driver assignment.');
    const account = await User.findById(driver.userId).session(session);
    if (driver.status !== 'active' || account?.status !== 'active') {
      throw driverError(409, DRIVER_ERROR_CODES.ACCOUNT_INACTIVE, 'The driver account is not active.', 'Activate the account before assigning a terminal trip.');
    }
    if (assignedRouteOnly && String(driver.assignedRouteId || '') !== String(routeId)) {
      throw driverError(409, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING, 'The selected route is not assigned to this driver.', 'Use the driver\'s assigned route.');
    }
    if (String(driver.assignedJeepneyId || '') !== String(jeepneyId)) {
      throw driverError(409, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING, 'The selected jeepney is not assigned to this driver.', 'Use the driver\'s assigned jeepney.');
    }
    const vehicle = await Jeepney.findOneAndUpdate({ _id: jeepneyId },
      { $set: { updatedAt: new Date() } }, { new: true, session });
    const route = await Route.findById(routeId).session(session);
    if (!vehicle || vehicle.status !== 'active' || vehicle.capacity <= 0) throw driverError(409, DRIVER_ERROR_CODES.JEEPNEY_INACTIVE, 'The assigned jeepney is inactive or has no usable capacity.', 'Ask an administrator to activate or repair the jeepney record.');
    if (vehicle.currentDriverId && String(vehicle.currentDriverId) !== String(driverId)) {
      throw driverError(409, DRIVER_ERROR_CODES.ASSIGNMENT_MISSING, 'This jeepney is assigned to another driver.', 'Use the jeepney assigned to your driver account.');
    }
    if (!route || route.status !== 'active') throw driverError(409, DRIVER_ERROR_CODES.ROUTE_INACTIVE, 'The assigned route is not active.', 'Ask an administrator to activate the route.');
    const terminal = resolveRouteTerminalStop(route);
    if (!terminal) throw driverError(409, DRIVER_ERROR_CODES.TERMINAL_NOT_CONFIGURED, 'The assigned route has no departure terminal.', 'Ask an administrator to configure the route terminal.');

    let trip = await Trip.findOne({ status: { $in: ['scheduled', 'active'] },
      $or: [{ driverId }, { jeepneyId }] }).session(session);
    if (trip && (String(trip.driverId) !== String(driverId) ||
      String(trip.jeepneyId) !== String(jeepneyId) || String(trip.routeId) !== String(routeId))) {
      throw driverError(409, DRIVER_ERROR_CODES.QUEUE_CONFLICT, 'The driver or jeepney already has a trip on another assignment.', 'Finish or resolve the existing trip before assigning another.');
    }
    if (!trip) {
      // A driver's explicit route choice must also drive GPS progression,
      // route subscriptions and request visibility after the profile reload.
      if (selectRoute) driver.assignedRouteId = routeId;
      driver.automaticJourneyPaused = false;
      driver.automaticJourneyCheck = { observations: 0 };
      await driver.save({ session });
      [trip] = await Trip.create([{
        flowVersion: require('../config/env').automaticGroupFlowEnabled ? 2 : 1, driverId, jeepneyId, routeId, status: 'scheduled', active: false,
        acceptRequests: false, operatingMode: 'terminal_queue', terminalQueueStatus: 'off_queue',
        routePathSnapshot: route.path?.coordinates?.length >= 2 ? route.path : undefined,
        terminalStopRef: terminal.stopRef, terminalLocation: terminal.location,
        terminalRadiusMeters: terminal.radiusMeters,
      }], { session });
    }
    if (trip.status === 'scheduled' && trip.operatingMode === 'terminal_queue' && trip.terminalQueueStatus === 'off_queue') {
      await Driver.updateOne({ _id: driverId }, {
        $set: { operatingMode: 'terminal_queue', terminalQueueStatus: 'off_queue', terminalStopRef: trip.terminalStopRef },
        $unset: { terminalQueueNumber: '', terminalCheckedInAt: '' },
      }, { session });
    }
    return trip;
  });
}

module.exports = { createTerminalIntent };
