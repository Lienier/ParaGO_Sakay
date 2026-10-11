const test = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const { migrate } = require('../scripts/migrate-pickup-retention.cjs');

test('pickup retention migration removes only the booking TTL, preserves records and is repeatable', async () => {
  const repl = await MongoMemoryReplSet.create({ binary: { version: '8.2.6' },
    replSet: { count: 1, ip: '127.0.0.1' } });
  try {
    const uri = repl.getUri('pickup_retention_isolated_test');
    assert.match(uri, /^mongodb:\/\/127\.0\.0\.1:/);
    await mongoose.connect(uri, { autoIndex: false, autoCreate: false });
    const bookings = mongoose.connection.collection('pickuprequests');
    const sessions = mongoose.connection.collection('authsessions');
    await bookings.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    await bookings.createIndex({ passengerId: 1 });
    await sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    const document = { _id: new mongoose.Types.ObjectId(), status: 'completed',
      expiresAt: new Date(Date.now() + 3600000), passengerId: new mongoose.Types.ObjectId() };
    await bookings.insertOne(document);
    assert.equal((await migrate()).recordsChanged, 0);
    await migrate();
    const indexes = await bookings.indexes();
    assert.ok(indexes.some(i => i.key.expiresAt === 1 && i.expireAfterSeconds == null));
    assert.ok(indexes.some(i => i.key.passengerId === 1));
    assert.equal((await sessions.indexes()).find(i => i.key.expiresAt === 1).expireAfterSeconds, 0);
    assert.deepEqual(await bookings.findOne({ _id: document._id }), document);
  } finally { await mongoose.disconnect(); await repl.stop(); }
});
