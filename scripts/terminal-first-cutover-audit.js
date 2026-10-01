// Read-only maintenance audit for the terminal-first driver cutover.
// This script never changes records or creates indexes.
const mongoose = require('mongoose');
const dotenv = require('dotenv');
const path = require('path');
const TripSession = require('../src/models/tripSession');
const RideSession = require('../src/models/rideSession');
const PickupRequest = require('../src/models/pickupRequest');
const Driver = require('../src/models/driver');

const CP_PATTERN = /^09\d{9}$/;
const normalizeLicense = (value) =>
  String(value || '').trim().replace(/\s+/g, ' ').toUpperCase();

const environment = process.argv.find((arg) => arg.startsWith('--environment='))?.split('=')[1] || 'local';
const envFile = environment === 'staging' ? '.env.staging' : '.env';
dotenv.config({ path: path.resolve(__dirname, '..', envFile) });

async function inspect() {
  const directTrips = await TripSession.find({
    operatingMode: 'route',
    status: { $in: ['scheduled', 'active'] },
  }).select('_id driverId jeepneyId routeId status active operatingMode').lean();
  const tripIds = directTrips.map((trip) => trip._id);
  const [rides, requests, drivers] = await Promise.all([
    RideSession.find({ tripSessionId: { $in: tripIds }, status: { $in: ['waiting', 'onboard'] } })
      .select('_id tripSessionId passengerId status boardedCount remainingCount').lean(),
    PickupRequest.find({ tripSessionId: { $in: tripIds }, status: { $in: ['pending', 'acknowledged'] } })
      .select('_id tripSessionId passengerId status partySize expiresAt').lean(),
    Driver.find({}).select('+licenseNumberNormalized userId phone licenseNumber licenseNumberNormalized status').lean(),
  ]);

  const licenseGroups = new Map();
  for (const driver of drivers) {
    const key = normalizeLicense(driver.licenseNumberNormalized || driver.licenseNumber);
    if (key) licenseGroups.set(key, [...(licenseGroups.get(key) || []), String(driver._id)]);
  }
  const duplicateLicenses = [...licenseGroups.entries()]
    .filter(([, ids]) => ids.length > 1)
    .map(([licenseNumber, driverIds]) => ({ licenseNumber, driverIds }));
  const invalidCp = drivers
    .filter((driver) => !CP_PATTERN.test(String(driver.phone || '').trim()))
    .map((driver) => ({ driverId: String(driver._id), userId: String(driver.userId), reason: driver.phone ? 'invalid' : 'missing' }));
  const missingLicense = drivers
    .filter((driver) => !normalizeLicense(driver.licenseNumberNormalized || driver.licenseNumber))
    .map((driver) => ({ driverId: String(driver._id), userId: String(driver.userId) }));
  const directTripImpact = directTrips.map((trip) => ({
    tripId: String(trip._id),
    driverId: trip.driverId && String(trip.driverId),
    jeepneyId: trip.jeepneyId && String(trip.jeepneyId),
    routeId: String(trip.routeId),
    status: trip.status,
    activeRides: rides.filter((ride) => String(ride.tripSessionId) === String(trip._id)),
    pendingRequests: requests.filter((request) => String(request.tripSessionId) === String(trip._id)),
  }));
  const blockers = {
    directRouteTrips: directTripImpact.length > 0,
    directRoutePassengerImpact: directTripImpact.some((trip) => trip.activeRides.length || trip.pendingRequests.length),
    invalidCp: invalidCp.length > 0,
    duplicateLicenses: duplicateLicenses.length > 0,
    missingLicense: missingLicense.length > 0,
  };
  return {
    mode: 'dry-run', environment, generatedAt: new Date().toISOString(),
    readyForEnforcement: !Object.values(blockers).some(Boolean),
    blockers, directTrips: directTripImpact, invalidCp, missingLicense, duplicateLicenses,
  };
}

async function run() {
  if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required for the audit.');
  await mongoose.connect(process.env.MONGO_URI, { autoIndex: false, autoCreate: false, serverSelectionTimeoutMS: 12000 });
  try { console.log(JSON.stringify(await inspect(), null, 2)); }
  finally { await mongoose.disconnect(); }
}

if (require.main === module) run().catch((error) => { console.error(`Terminal-first audit failed: ${error.message}`); process.exitCode = 1; });
module.exports = { inspect, normalizeLicense };
