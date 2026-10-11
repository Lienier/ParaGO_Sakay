const Jeepney = require('../models/jeepney');
const Driver = require('../models/driver');
const TripSession = require('../models/tripSession');
const Route = require('../models/route');

const validCoordinates = (coordinates) => Array.isArray(coordinates) &&
  coordinates.length >= 2 && coordinates.slice(0, 2).every(Number.isFinite) &&
  Math.abs(coordinates[0]) <= 180 && Math.abs(coordinates[1]) <= 90;

async function getAdminFleet() {
  const [jeeps, drivers, trips, routes] = await Promise.all([
    Jeepney.find().select('plateNumber jeepneyName status capacity currentDriverId lastKnownLocation lastSeenAt latestLocationOrder').lean(),
    Driver.find().select('userId assignedJeepneyId assignedRouteId status').populate('userId', 'fullName').lean(),
    TripSession.find({ status: 'active' }).sort({ createdAt: -1 }).select('jeepneyId driverId routeId occupancyCount terminalQueueStatus operatingMode').lean(),
    Route.find().select('name code status').lean(),
  ]);
  const driverById = new Map(drivers.map(d => [String(d._id), d]));
  const driverByJeep = new Map(drivers.filter(d => d.assignedJeepneyId).map(d => [String(d.assignedJeepneyId), d]));
  const routeById = new Map(routes.map(r => [String(r._id), r]));
  const tripByJeep = new Map();
  for (const trip of trips) if (!tripByJeep.has(String(trip.jeepneyId))) tripByJeep.set(String(trip.jeepneyId), trip);
  return {
    generatedAt: new Date().toISOString(),
    vehicles: jeeps.map(j => {
      const trip = tripByJeep.get(String(j._id));
      const driver = driverById.get(String(j.currentDriverId || trip?.driverId || '')) || driverByJeep.get(String(j._id));
      const routeId = String(trip?.routeId || driver?.assignedRouteId || '');
      const route = routeById.get(routeId);
      const coordinates = j.lastKnownLocation?.coordinates;
      return {
        jeepneyId: String(j._id), plateNumber: j.plateNumber, jeepneyName: j.jeepneyName || '',
        status: j.status, capacity: j.capacity ?? null, driverId: driver ? String(driver._id) : '',
        driverName: driver?.userId?.fullName || '', driverStatus: driver?.status || '',
        routeId, routeName: route?.name || '', routeCode: route?.code || '',
        tripId: trip ? String(trip._id) : '', occupancyCount: trip?.occupancyCount ?? 0,
        terminalQueueStatus: trip?.terminalQueueStatus || '', operatingMode: trip?.operatingMode || '',
        latitude: validCoordinates(coordinates) ? coordinates[1] : null,
        longitude: validCoordinates(coordinates) ? coordinates[0] : null,
        lastSeenAt: j.lastSeenAt?.toISOString() || null,
        capturedAt: j.latestLocationOrder?.capturedAt?.toISOString() || j.lastSeenAt?.toISOString() || null,
        streamId: j.latestLocationOrder?.streamId || '', sequence: j.latestLocationOrder?.sequence ?? null,
      };
    }).sort((a, b) => a.plateNumber.localeCompare(b.plateNumber)),
  };
}
module.exports = { getAdminFleet, validCoordinates };
