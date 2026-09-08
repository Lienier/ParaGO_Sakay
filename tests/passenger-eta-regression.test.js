const { test } = require('node:test');
const assert = require('node:assert/strict');

test('ETA validates current state before cached results and refreshes on movement', async (t) => {
  const Trip = require('../src/models/tripSession');
  const Route = require('../src/models/route');
  const axios = require('axios');
  const env = require('../src/config/env');
  const transient = require('../src/services/transientState.service');
  const now = new Date();
  const trip = {
    _id: 'eta-regression', status: 'active', routeId: 'route',
    jeepneyId: { _id: 'jeep', plateNumber: 'TEST', status: 'active',
      lastKnownLocation: { coordinates: [121.002, 14.6] }, lastSeenAt: now },
  };
  t.mock.method(Trip, 'findById', () => ({ populate: async () => trip }));
  t.mock.method(Route, 'findById', async () => ({ path: {
    coordinates: [[121, 14.6], [121.01, 14.6], [121.02, 14.6]],
  } }));
  t.mock.method(transient, 'getLatestJeepLocation', async () => ({ value: null }));
  t.mock.method(transient, 'coalesceEtaRequest', async ({ loader }) => loader());
  const google = t.mock.method(axios, 'post', async () => ({ data: { routes: [{
    duration: '120s', staticDuration: '100s', distanceMeters: 1000,
  }] } }));
  const oldKey = env.googleRoutesApiKey;
  env.googleRoutesApiKey = 'test-key';
  const modulePath = require.resolve('../src/services/passengerEta.service');
  delete require.cache[modulePath];
  t.after(() => { env.googleRoutesApiKey = oldKey; delete require.cache[modulePath]; });
  const { calculatePassengerEta } = require(modulePath);
  const args = { tripId: trip._id, destination: { latitude: 14.6, longitude: 121.018 } };
  const first = await calculatePassengerEta(args);
  assert.equal(first.durationSeconds, 120);
  await calculatePassengerEta(args);
  assert.equal(google.mock.callCount(), 1);
  trip.status = 'completed';
  await assert.rejects(calculatePassengerEta(args), /active trip/);
  trip.status = 'active';
  trip.jeepneyId.lastSeenAt = new Date(Date.now() - 61000);
  await assert.rejects(calculatePassengerEta(args), /fresh enough/);
  trip.jeepneyId.lastSeenAt = new Date();
  trip.jeepneyId.lastKnownLocation.coordinates = [121.004, 14.6];
  await calculatePassengerEta(args);
  assert.equal(google.mock.callCount(), 2);
  trip.jeepneyId.lastKnownLocation.coordinates = [121.019, 14.6];
  await assert.rejects(calculatePassengerEta(args), /already passed/);
});
