const Policy = require('../models/mobileReleasePolicy');
const Release = require('../models/mobileRelease');
const ApiError = require('../utils/apiError');

const appFor = user => ({ DRIVER: 'driver', PASSENGER: 'passenger' })[user?.role];
const buildNumber = value => /^\d{1,10}$/.test(String(value || '')) && Number(value) <= 2100000000 ? Number(value) : 0;
async function catalog(app) {
  if (!['driver', 'passenger'].includes(app)) throw new ApiError(400, 'Unknown application');
  const policy = await Policy.findById(app).lean();
  const release = policy?.latestBuild ? await Release.findOne({ app, build: policy.latestBuild, publishedAt: { $ne: null } })
    .select('build version url notes publishedAt sha256 size -_id').lean() : null;
  return { app, latest: release, minimumBuild: release ? policy.minimumBuild : 0, message: policy?.message || '' };
}
async function hasJourney(user) {
  if (user.role === 'DRIVER') {
    const driver = await require('../models/driver').findOne({ userId: user._id }).select('_id').lean();
    return Boolean(driver && await require('../models/tripSession').exists({ driverId: driver._id, status: 'active' }));
  }
  const passenger = await require('../models/passenger').findOne({ userId: user._id }).select('_id').lean();
  if (!passenger) return false;
  const id = passenger._id;
  if (await require('../models/rideSession').exists({ passengerId: id, status: { $in: ['waiting', 'onboard'] } })) return true;
  return Boolean(await require('../models/pickupRequest').exists({ passengerId: id,
    status: { $in: ['pending', 'acknowledged', 'transfer_offered'] }, expiresAt: { $gt: new Date() } }));
}
async function status(user, build) {
  const app = appFor(user);
  if (!app) return { latest: null, required: false, deferred: false };
  const result = await catalog(app);
  const required = result.minimumBuild > buildNumber(build);
  return { ...result, required, deferred: required && await hasJourney(user) };
}
// Only new journeys are restricted. Completion, tracking, para alerts, bookings
// already in progress, support, authentication and read APIs stay available.
function startsJourney(req) {
  const path = String(req.originalUrl || '').split('?')[0].replace(/^\/api\/v1(?=\/)/, '').replace(/\/$/, '');
  return req.method === 'POST' && ['/trips', '/pickup-requests'].includes(path) ||
    req.method === 'PATCH' && /^\/trips\/[^/]+\/start$/.test(path);
}
async function enforceNewJourney(req) {
  const app = appFor(req.user);
  if (!app || !startsJourney(req)) return;
  const config = require('../config/env');
  if (config.automaticGroupFlowEnabled && config.automaticGroupMinimumBuild > buildNumber(req.get('X-App-Build'))) throw new ApiError(426, 'Update the app before starting a new journey.', [], 'APP_UPDATE_REQUIRED');
  const policy = await Policy.findById(app).lean();
  if (policy?.minimumBuild > buildNumber(req.get('X-App-Build'))) {
    throw new ApiError(426, 'A major update is required before starting a new journey. Download it at https://downloads.sakaygaray.com', [], 'APP_UPDATE_REQUIRED');
  }
}
module.exports = { catalog, status, hasJourney, buildNumber, enforceNewJourney, startsJourney };
