// Default is read-only. Never deletes trip, booking, ride or audit history.
const fs = require('node:fs');
const path = require('node:path');
const mongoose = require('mongoose');
const env = require('dotenv').parse(fs.readFileSync(path.resolve(__dirname, '../.env')));
const out = path.resolve(__dirname, '../artifacts/driver_queue_fix_2026-10-13');
async function main() {
  try {
    await mongoose.connect(env.MONGO_URI || env.MONGODB_URI, { autoIndex: false, autoCreate: false, serverSelectionTimeoutMS: 15000 });
    const Trip = require('../src/models/tripSession');
    const Ride = require('../src/models/rideSession');
    const Pickup = require('../src/models/pickupRequest');
    const Queue = require('../src/models/terminalQueue');
    const Driver = require('../src/models/driver');
    if (process.argv.includes('--apply')) {
      const preview = JSON.parse(fs.readFileSync(path.join(out, 'queue-preview.json')));
      if (Date.now() - Date.parse(preview.checkedAt) > 24 * 60 * 60 * 1000) throw Error('Preview expired; run the read-only check again');
      const ids = preview.entries.filter(entry => entry.canClear).map(entry => new mongoose.Types.ObjectId(entry.tripId));
      const targets = await Trip.find({ _id: { $in: ids } }).lean();
      const driverIds = targets.map(trip => trip.driverId).filter(Boolean);
      const backup = { at: new Date().toISOString(), trips: targets,
        drivers: await Driver.find({ _id: { $in: driverIds } }).lean(),
        pickups: await Pickup.find({ tripSessionId: { $in: ids } }).lean(),
        rides: await Ride.find({ tripSessionId: { $in: ids } }).lean(),
        counters: await Queue.find({ _id: { $in: targets.map(trip => trip.routeId) } }).lean() };
      const backupDir = path.resolve(__dirname, '../.secure-backups');
      fs.mkdirSync(backupDir, { recursive: true });
      const backupFile = path.join(backupDir, `terminal-queue-reset-${Date.now()}.json`);
      fs.writeFileSync(backupFile, JSON.stringify(backup, null, 2), { flag: 'wx' });
      const admin = await require('../src/models/user').findOne({ role: 'ADMIN', status: 'active' }).select('_id');
      if (!admin) throw Error('No active administrator is available for the maintenance audit');
      const results = [];
      for (const trip of targets) {
        if (!['active', 'scheduled'].includes(trip.status) || trip.operatingMode !== 'terminal_queue') {
          results.push({ tripId: String(trip._id), result: 'already cleared' }); continue;
        }
        const saved = await require('../src/services/terminalQueue.service').cancel({ tripId: trip._id,
          actor: { _id: admin._id, role: 'ADMIN' }, requestId: `maintenance-cancel-${trip._id}`,
          reason: 'User requested current terminal queues cleared; local maintenance with private backup' });
        results.push({ tripId: String(saved._id), result: saved.status });
      }
      const remaining = await Trip.countDocuments({ status: { $in: ['active', 'scheduled'] }, operatingMode: 'terminal_queue' });
      const proof = { appliedAt: new Date().toISOString(), backedUp: true, results, remainingEntries: remaining, historicalRecordsDeleted: 0 };
      fs.writeFileSync(path.join(out, 'queue-reset.json'), JSON.stringify(proof, null, 2));
      console.log(JSON.stringify(proof));
      return;
    }
    const trips = await Trip.find({ status: { $in: ['scheduled', 'active'] }, operatingMode: 'terminal_queue' }).lean();
    const entries = [];
    for (const trip of trips) {
      const rides = await Ride.find({ tripSessionId: trip._id, status: { $in: ['onboard', 'waiting'] } }).select('remainingCount').lean();
      const occupied = Math.max(trip.occupancyCount || 0, (trip.manualOccupancyCount || 0) + rides.reduce((sum, ride) => sum + (ride.remainingCount ?? 1), 0));
      const bookings = await Pickup.countDocuments({ tripSessionId: trip._id, status: { $in: ['pending', 'acknowledged', 'transfer_offered'] } });
      entries.push({ tripId: String(trip._id), driverId: String(trip.driverId || ''), routeId: String(trip.routeId), status: trip.status,
        queueStatus: trip.terminalQueueStatus, occupied, pendingBookings: bookings, canClear: occupied === 0 });
    }
    fs.mkdirSync(out, { recursive: true });
    const preview = { checkedAt: new Date().toISOString(), currentEntries: entries.length, clearable: entries.filter(entry => entry.canClear).length,
      occupiedEntries: entries.filter(entry => !entry.canClear).length, queueCounters: await Queue.countDocuments(), entries };
    fs.writeFileSync(path.join(out, 'queue-preview.json'), JSON.stringify(preview, null, 2));
    console.log(JSON.stringify(preview));
  } finally { await mongoose.disconnect(); }
}
main().catch(error => { console.error('Queue inspection failed: ' + error.name); process.exitCode = 1; });
