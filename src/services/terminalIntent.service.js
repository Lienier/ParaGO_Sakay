const Driver = require('../models/driver');
const User = require('../models/user');
const Jeepney = require('../models/jeepney');
const Route = require('../models/route');
const Trip = require('../models/tripSession');
const ApiError = require('../utils/apiError');
const queue = require('./terminalQueue.service');
const { resolveRouteTerminalStop } = require('./hybridDispatch.service');

async function createTerminalIntent({ driverId, routeId, jeepneyId, assignedRouteOnly = false }) {
  return queue.transaction(routeId, async session => {
    // Lock the driver and vehicle as well as the route. Different-route requests
    // must not create a competing intent or race with arrival profile updates.
    const driver = await Driver.findOneAndUpdate({ _id: driverId },
      { $set: { updatedAt: new Date() } }, { new: true, session });
    if (!driver) throw new ApiError(404, 'Driver not found');
    const account = await User.findById(driver.userId).session(session);
    if (driver.status !== 'active' || account?.status !== 'active') {
      throw new ApiError(409, 'Driver and driver account must be active');
    }
    if (assignedRouteOnly && String(driver.assignedRouteId || '') !== String(routeId)) {
      throw new ApiError(409, 'Use the driver\'s assigned route for terminal assignment');
    }
    if (String(driver.assignedJeepneyId || '') !== String(jeepneyId)) {
      throw new ApiError(409, 'Use the driver\'s assigned jeepney for terminal assignment');
    }
    const vehicle = await Jeepney.findOneAndUpdate({ _id: jeepneyId },
      { $set: { updatedAt: new Date() } }, { new: true, session });
    const route = await Route.findById(routeId).session(session);
    if (!vehicle || vehicle.status !== 'active' || vehicle.capacity <= 0) throw new ApiError(409, 'Jeepney is not active or has no capacity');
    if (vehicle.currentDriverId && String(vehicle.currentDriverId) !== String(driverId)) {
      throw new ApiError(409, 'Jeepney is assigned to another driver');
    }
    if (!route || route.status !== 'active') throw new ApiError(409, 'Route is not active');
    const terminal = resolveRouteTerminalStop(route);
    if (!terminal) throw new ApiError(409, 'Selected route has no terminal stop configured');

    let trip = await Trip.findOne({ status: { $in: ['scheduled', 'active'] },
      $or: [{ driverId }, { jeepneyId }] }).session(session);
    if (trip && (String(trip.driverId) !== String(driverId) ||
      String(trip.jeepneyId) !== String(jeepneyId) || String(trip.routeId) !== String(routeId))) {
      throw new ApiError(409, 'Driver or jeepney already has a trip on another assignment; resolve it first');
    }
    if (!trip) {
      [trip] = await Trip.create([{
        driverId, jeepneyId, routeId, status: 'scheduled', active: false,
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
