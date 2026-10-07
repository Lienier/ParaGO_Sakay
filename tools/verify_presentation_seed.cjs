// Verification uses a temporary local replica set, never .env or Atlas.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const seed = require('../scripts/seed-presentation');
async function main() {
  let repl;
  try {
    const binary = path.join(os.tmpdir(), 'parago-mongodb-binaries/mongod-x64-win32-8.2.6.exe');
    repl = await MongoMemoryReplSet.create({ binary: { version: '8.2.6', ...(fs.existsSync(binary) ? { systemBinary: binary } : {}) },
      replSet: { count: 1, ip: '127.0.0.1' } });
    const uri = repl.getUri('sakay_presentation');
    seed.localBoundary(uri);
    assert.throws(() => seed.localBoundary('mongodb://127.0.0.1/production'));
    assert.throws(() => seed.localBoundary('mongodb://remote.example/sakay_presentation'));
    assert.throws(() => seed.options(['--live', '--apply']));
    await mongoose.connect(uri, { autoIndex: false });
    const opts = seed.options(['--date=2026-10-08']);
    const rows = await seed.buildDataset(opts, 'Temporary-Local-Verification!');
    // Test the live-mode transformation against a local existing admin.
    const admin = await seed.models.User.create({ email: opts.adminEmail, fullName: 'Existing Local Administrator',
      role: 'ADMIN', status: 'active', passwordHash: 'untouched-existing-hash' });
    await seed.useExistingAdmin(rows, opts.adminEmail);
    const expected = Object.values(rows).reduce((sum, docs) => sum + docs.length, 0);
    assert.equal(await seed.applyDataset(rows, { ensureIndexes: true }), expected);
    for (const [name, docs] of Object.entries(rows)) {
      assert.equal(await seed.models[name].countDocuments({ _id: { $in: docs.map(doc => doc._id) } }), docs.length);
      for (const doc of docs) {
        seed.models[name].schema.eachPath((field, schema) => {
          if (!schema.options.ref || !doc[field]) return;
          const references = rows[schema.options.ref] || [];
          assert.ok(references.some(target => String(target._id) === String(doc[field])) ||
            (schema.options.ref === 'User' && String(doc[field]) === String(admin._id)), `${name}.${field} broken reference`);
        });
      }
    }
    const user = await seed.models.User.findById(rows.User[0]._id).select('+passwordHash');
    assert.equal(await require('bcryptjs').compare('Temporary-Local-Verification!', user.passwordHash), true);
    await seed.models.Route.updateOne({ _id: rows.Route[0]._id }, { $set: { name: 'Existing edit must survive' } });
    assert.equal(await seed.applyDataset(rows), 0);
    assert.equal((await seed.models.Route.findById(rows.Route[0]._id)).name, 'Existing edit must survive');
    assert.equal((await seed.models.User.findById(admin._id).select('+passwordHash')).passwordHash, 'untouched-existing-hash');
    for (const ride of rows.RideSession) {
      assert.equal(ride.remainingCount, 0);
      assert.equal(ride.regularTotal, ride.partySize * ride.fareSnapshot.amount);
    }
    const result = { verifiedAt: new Date().toISOString(), target: 'temporary local MongoDB replica set',
      inserted: expected, rerunInserted: 0, checks: ['schema validation', 'all references', 'real unique/geospatial indexes',
        'password hashing', 'existing admin credentials retained', 'existing edits retained', 'completed ride totals', 'target guards'],
      liveDatabaseAccessed: false };
    fs.mkdirSync(path.resolve(__dirname, '../artifacts/presentation_seed_2026-10-07'), { recursive: true });
    fs.writeFileSync(path.resolve(__dirname, '../artifacts/presentation_seed_2026-10-07/verification.json'), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await mongoose.disconnect();
    if (repl) await repl.stop();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
