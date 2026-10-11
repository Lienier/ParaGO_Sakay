// Keep booking/ride history. Run after validation and before deploying the
// matching schema; this changes one index and never changes/deletes records.
const mongoose = require('mongoose');
async function migrate(connection = mongoose.connection) {
  const collection = connection.collection('pickuprequests');
  const indexes = await collection.indexes();
  for (const index of indexes) {
    if (Object.keys(index.key).length === 1 && index.key.expiresAt === 1 && index.expireAfterSeconds != null) {
      await collection.dropIndex(index.name);
    }
  }
  await collection.createIndex({ expiresAt: 1 });
  return { collection: 'pickuprequests', recordsChanged: 0, ttlRemoved: true };
}
module.exports = { migrate };
if (require.main === module) {
  require('dotenv').config({ quiet: true });
  (async () => { try {
    await mongoose.connect(process.env.MONGO_URI || process.env.MONGODB_URI, { autoIndex: false, autoCreate: false });
    console.log(JSON.stringify(await migrate()));
  } catch (e) { console.error('Pickup retention migration failed: ' + e.name); process.exitCode = 1; }
  finally { await mongoose.disconnect(); } })();
}
