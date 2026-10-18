const Driver = require('../models/driver');
const Trip = require('../models/tripSession');
const { resolveRouteTerminalStop } = require('./hybridDispatch.service');
const { haversineMeters } = require('../utils/geo');

// Informational only. Never infer queue membership or perform check-in here.
function terminalLocationHint(driver, trips, { now = new Date(), automatic = false } = {}) {
  const jeep = driver.assignedJeepneyId, route = driver.assignedRouteId;
  if (!jeep?._id || !route?._id) return null;
  const terminal = resolveRouteTerminalStop(route);
  const point = jeep.lastKnownLocation?.coordinates, target = terminal?.location?.coordinates;
  if (!terminal || !Array.isArray(point) || point.length !== 2 || !Array.isArray(target) || target.length !== 2 ||
      ![...point, ...target].every(Number.isFinite) || Math.abs(point[0]) > 180 || Math.abs(point[1]) > 90 ||
      Math.abs(target[0]) > 180 || Math.abs(target[1]) > 90) return null;
  const distance = haversineMeters(target[1], target[0], point[1], point[0]);
  if (distance > (terminal.radiusMeters || 75)) return null;
  const own = trips.find(t => String(t.driverId) === String(driver._id));
  // Existing terminal entries already have authoritative queue/arrival cards.
  if (own?.operatingMode === 'terminal_queue') return null;
  const capturedAt = jeep.latestLocationOrder?.capturedAt || jeep.lastSeenAt;
  const age = capturedAt ? +now - +new Date(capturedAt) : NaN;
  const fresh = Number.isFinite(age) && age >= 0 && age <= 60000;
  let reason;
  if (!fresh) reason = 'Old GPS location. Open the Driver app to update it.';
  else if (driver.userId?.status !== 'active') reason = 'Driver account is not active.';
  else if (route.status !== 'active') reason = 'Route is not active.';
  else if (jeep.status !== 'active' || !(jeep.capacity > 0)) reason = 'Jeep must be active and have seats configured.';
  else if (jeep.currentDriverId && String(jeep.currentDriverId) !== String(driver._id)) reason = 'Jeep is assigned to another driver.';
  else if (own) reason = 'Trip is still on route. End it when empty before rejoining.';
  else if (automatic && !driver.automaticJourneyPaused) reason = 'Waiting for the automatic GPS arrival checks.';
  else reason = 'Open Trip and choose a route to join the terminal.';
  return {
    driverId: String(driver._id), driverName: driver.userId?.fullName || 'Driver',
    jeepneyId: String(jeep._id), plateNumber: jeep.plateNumber || 'Jeep',
    routeId: { _id: String(route._id), name: route.name, code: route.code, direction: route.direction },
    terminalName: terminal.name || terminal.stopRef || 'Terminal', distanceMeters: Math.round(distance),
    lastUpdateAt: Number.isFinite(age) ? new Date(capturedAt).toISOString() : null,
    fresh, state: fresh ? (own ? 'On route' : 'Not queued') : 'Old location', reason,
  };
}

async function getTerminalLocationHints({ now = new Date() } = {}) {
  const [drivers, trips] = await Promise.all([
    Driver.find().select('userId assignedJeepneyId assignedRouteId automaticJourneyPaused')
      .populate('userId', 'fullName status')
      .populate('assignedJeepneyId', 'plateNumber status capacity currentDriverId lastKnownLocation lastSeenAt latestLocationOrder')
      .populate('assignedRouteId', 'name code direction status terminal stops').lean(),
    Trip.find({ status: { $in: ['scheduled', 'active'] } }).select('driverId operatingMode').lean(),
  ]);
  const config = require('../config/env');
  return drivers.map(d => terminalLocationHint(d, trips, { now,
    automatic: config.automaticGroupFlowEnabled && config.automaticDriverLifecycleEnabled }))
    .filter(Boolean).sort((a, b) => Number(b.fresh) - Number(a.fresh) || a.plateNumber.localeCompare(b.plateNumber));
}
module.exports = { terminalLocationHint, getTerminalLocationHints };
