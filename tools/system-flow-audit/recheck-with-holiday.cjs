// Only the two audited date-dependent suites use this wrapper.
const { beforeEach } = require('node:test');
require(process.env.AUDIT_TEST_FILE);
// Register after each suite's cleanup hook so its dropDatabase cannot erase the fixture.
beforeEach(async () => {
  const mongoose = require('mongoose');
  if (mongoose.connection.host !== '127.0.0.1') throw Error('Holiday fixture must use the temporary local database');
  const date = require('../../src/services/operatingRules.service').manilaDate();
  await require('../../src/models/codingHoliday').updateOne({ date },
    { $set: { name: 'Synthetic audit holiday: isolate non-coding scenarios from wall-clock date' } }, { upsert: true });
});
