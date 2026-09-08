// Read-only by default. Apply only in a maintenance window with API/worker writes stopped.
const mongoose = require('mongoose');
const { mongoUri } = require('../src/config/env');
const Trip = require('../src/models/tripSession');
const Queue = require('../src/models/terminalQueue');
const Action = require('../src/models/terminalQueueAction');

async function inspect() {
  const trips = await Trip.find({ status: { $in: ['active', 'scheduled'] }, operatingMode: 'terminal_queue' }).lean();
  const conflicts = [];
  for (const field of ['driverId', 'jeepneyId', 'position', 'loading']) {
    const seen = new Map();
    for (const trip of trips) {
      if (field !== 'position' && trip.status !== 'active') continue;
      if (field === 'loading' && trip.terminalQueueStatus !== 'loading') continue;
      const key = field === 'position' ? `${trip.routeId}:${trip.terminalQueueNumber}` : field === 'loading' ? String(trip.routeId) : String(trip[field]);
      if (seen.has(key)) conflicts.push({ field, trips: [seen.get(key), String(trip._id)] });
      seen.set(key, String(trip._id));
    }
  }
  for (const trip of trips) {
    if (!trip.driverId || !trip.jeepneyId || !Number.isSafeInteger(trip.terminalQueueNumber) || trip.terminalQueueNumber < 1 ||
        !['waiting', 'loading', 'skipped'].includes(trip.terminalQueueStatus))
      conflicts.push({ field: 'missing_or_ambiguous_state', trips: [String(trip._id)] });
  }
  return { trips, conflicts };
}
async function run() {
  // Avoid implicit index writes during a dry run.
  mongoose.set('autoIndex', false);
  await mongoose.connect(mongoUri, { autoIndex: false, autoCreate: false });
  try {
    const { trips, conflicts } = await inspect();
    console.log(JSON.stringify({ mode: process.argv.includes('--apply') ? 'apply' : 'dry-run', entries: trips.length, conflicts }, null, 2));
    if (conflicts.length) { process.exitCode = 1; return; }
    if (!process.argv.includes('--apply')) return;
    for (const trip of trips) {
      await Queue.updateOne({ _id: trip.routeId }, { $max: { nextPosition: trip.terminalQueueNumber }, $setOnInsert: { revision: 0 } }, { upsert: true });
      await Trip.updateOne({ _id: trip._id }, { $set: { acceptRequests: trip.terminalQueueStatus === 'loading' }, $unset: { inactivityPausedAt: 1 } });
    }
    await Trip.createIndexes(); await Queue.createIndexes(); await Action.createIndexes();
    console.log('Queue records and indexes prepared. Start the secured API and worker to reconcile promotion.');
  } finally { await mongoose.disconnect(); }
}
if (require.main === module) run().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { inspect };
