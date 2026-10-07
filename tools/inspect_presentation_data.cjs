// Read-only inventory of the configured database. No credentials or personal data in the report.
const fs = require('node:fs');
const path = require('node:path');
const mongoose = require('mongoose');
const { readEnvironmentFile, parseMongoTarget } = require('../scripts/start-staging');
mongoose.set('autoIndex', false);
const root = path.resolve(__dirname, '..');
async function main() {
  const env = readEnvironmentFile(path.join(root, '.env'));
  const uri = env.MONGO_URI || env.MONGODB_URI;
  parseMongoTarget(uri, 'Configured MongoDB');
  try {
    await mongoose.connect(uri, { autoIndex: false, autoCreate: false, serverSelectionTimeoutMS: 12000 });
    const db = mongoose.connection.db;
    const names = ['users', 'admins', 'drivers', 'passengers', 'routes', 'jeepneys', 'tripsessions', 'pickuprequests', 'ridesessions', 'supportthreads', 'notifications'];
    const results = await Promise.all(names.map(async name => [name, await db.collection(name).countDocuments()]));
    const routes = await db.collection('routes').find({}, { projection: { name: 1, code: 1, status: 1, stops: 1, terminal: 1, path: 1, fareConfig: 1 } }).toArray();
    const activeAdmins = await db.collection('users').countDocuments({ role: 'ADMIN', status: 'active' });
    const drivers = await db.collection('drivers').find({}, { projection: { userId: 1, status: 1, assignedRouteId: 1, assignedJeepneyId: 1 } }).toArray();
    const trips = await db.collection('tripsessions').aggregate([{ $group: { _id: '$status', count: { $sum: 1 } } }]).toArray();
    const rides = await db.collection('ridesessions').aggregate([{ $group: { _id: '$status', count: { $sum: 1 } } }]).toArray();
    const jeepneys = await db.collection('jeepneys').find({}, { projection: { status: 1, plateNumber: 1, capacity: 1, currentDriverId: 1 } }).toArray();
    const users = await db.collection('users').find({ role: { $in: ['ADMIN', 'DRIVER', 'PASSENGER'] } },
      { projection: { email: 1, role: 1, status: 1 } }).toArray();
    const presentationDate = '2026-10-08';
    const candidates = drivers.map(driver => {
      const jeepney = jeepneys.find(vehicle => String(vehicle._id) === String(driver.assignedJeepneyId));
      const route = routes.find(item => String(item._id) === String(driver.assignedRouteId));
      const user = users.find(item => String(item._id) === String(driver.userId));
      const digits = String(jeepney?.plateNumber || '').replace(/\D/g, '');
      return { driverId: String(driver._id), routeId: route ? String(route._id) : null, routeCode: route?.code,
        driverActive: driver.status === 'active', vehicleActive: jeepney?.status === 'active',
        accountActive: user?.role === 'DRIVER' && user?.status === 'active',
        plateLastDigit: digits ? Number(digits.slice(-1)) : null,
        restrictedOnThursday: !digits || [7, 8].includes(Number(digits.slice(-1))),
        capacity: jeepney?.capacity,
        vehicleDriverMatches: String(jeepney?.currentDriverId) === String(driver._id) };
    });
    const report = { inspectedAt: new Date().toISOString(), readOnly: true, counts: Object.fromEntries(results), activeAdmins,
      routes: routes.map(route => ({ id: String(route._id), name: route.name, code: route.code, status: route.status,
        stops: (route.stops || []).length, terminalConfigured: Boolean(route.terminal?.enabled && route.terminal?.location?.coordinates?.length === 2),
        terminalName: route.terminal?.name, terminalStopRef: route.terminal?.stopRef, terminalCoordinates: route.terminal?.location?.coordinates,
        assignedDrivers: drivers.filter(driver => String(driver.assignedRouteId) === String(route._id)).length })),
      assignedDrivers: drivers.filter(driver => driver.assignedRouteId && driver.assignedJeepneyId).length,
      tripStatuses: trips, rideStatuses: rides, presentationDate,
      driverReadiness: candidates,
      eligibleAssignedDriversForThursday: candidates.filter(item => item.routeId && item.driverActive && item.accountActive && item.vehicleActive && !item.restrictedOnThursday && item.vehicleDriverMatches).length };
    const eligible = candidates.filter(item => item.routeId && item.driverActive && item.accountActive && item.vehicleActive && !item.restrictedOnThursday && item.vehicleDriverMatches);
    const secureDirectory = path.join(root, '.secure-backups');
    fs.mkdirSync(secureDirectory, { recursive: true });
    fs.writeFileSync(path.join(secureDirectory, 'presentation-existing-accounts.json'), JSON.stringify({
      inspectedAt: report.inspectedAt, passwordNote: 'Use the existing account passwords. No passwords were read or changed.',
      admins: users.filter(user => user.role === 'ADMIN' && user.status === 'active').map(user => ({ email: user.email })),
      drivers: eligible.map(candidate => {
        const driver = drivers.find(item => String(item._id) === candidate.driverId);
        const user = users.find(item => String(item._id) === String(driver.userId));
        const vehicle = jeepneys.find(item => String(item._id) === String(driver.assignedJeepneyId));
        return { email: user.email, routeCode: candidate.routeCode, plateNumber: vehicle.plateNumber, capacity: vehicle.capacity };
      }),
      passengers: users.filter(user => user.role === 'PASSENGER' && user.status === 'active').slice(0, 5).map(user => ({ email: user.email })),
    }, null, 2), { mode: 0o600 });
    const directory = path.join(root, 'artifacts/presentation_seed_2026-10-07');
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, 'existing_data_inventory.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  } finally { await mongoose.disconnect(); }
}
main().catch(error => { console.error(`Read-only inventory failed (${error.name}); check the configured database connection.`); process.exitCode = 1; });
