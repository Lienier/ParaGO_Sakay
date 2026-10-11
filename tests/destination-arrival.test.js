const { test } = require('node:test');
const assert = require('node:assert/strict');
const { evaluateArrival, destinationKey } = require('../src/utils/destinationArrival');
const member = (lng, status = 'onboard') => ({ destinationLocation: { coordinates: [lng, 14] }, status });
const members = [member(121), member(121.0003)];
const start = new Date('2026-10-09T00:00:00Z');
const observation = (seconds, changes = {}) => ({ streamId: 'stream-a', sequence: seconds + 1,
  longitude: 121, latitude: 14, accuracyMeters: 10, speedMetersPerSecond: 0,
  capturedAt: new Date(+start + seconds * 1000), ...changes });
function step(seconds, previous = {}, changes = {}, candidates = members) {
  return evaluateArrival({ members: candidates, observation: observation(seconds, changes), previous, now: new Date(+start + seconds * 1000) });
}
test('three distinct observations over ten seconds are required', () => {
  const first = step(0); const second = step(5, first.state);
  assert.equal(second.reachedKey, null);
  assert.equal(step(10, second.state).reachedKey, destinationKey(members[0]));
  assert.equal(step(0, first.state).state.observations, 1);
  assert.equal(step(2, step(1, first.state).state).reachedKey, null);
});
test('completed nearby stop keeps another stop from inheriting its dwell', () => {
  const candidates = [member(121, 'completed'), member(121.0003)];
  const first = step(0, {}, {}, candidates); const second = step(5, first.state, {}, candidates);
  assert.equal(step(10, second.state, {}, candidates).reachedKey, destinationKey(candidates[0]));
  const next = step(15, second.state, { longitude: 121.0003 }, candidates);
  assert.equal(next.state.observations, 1); assert.equal(next.reachedKey, null);
});
for (const [name, changes] of Object.entries({ moving: { speedMetersPerSecond: 2 }, unknown: { speedMetersPerSecond: null },
  missing: { speedMetersPerSecond: undefined }, inaccurate: { accuracyMeters: 31 }, malformed: { longitude: null },
  stale: { capturedAt: new Date(+start - 20000) }, future: { capturedAt: new Date(+start + 20000) } })) {
  test(`${name} GPS resets arrival`, () => assert.equal(step(5, step(0).state, changes).reachedKey, null));
}
test('stream changes and long gaps start a new arrival check', () => {
  const old = step(5, step(0).state);
  assert.equal(step(10, old.state, { streamId: 'stream-b' }).state.observations, 1);
  assert.equal(step(25, old.state).state.observations, 1);
});
test('drive-by does not count a destination arrival', () => assert.equal(step(10, step(5, step(0).state).state, { longitude: 121.002 }).reachedKey, null));
