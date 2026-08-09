const test = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const Passenger = require('../src/models/passenger');

test('new passenger profiles do not create a partial GeoJSON location', () => {
  const passenger = new Passenger({ userId: new mongoose.Types.ObjectId() });

  assert.equal(passenger.lastKnownLocation, undefined);
});
