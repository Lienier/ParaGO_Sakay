const { test } = require('node:test');
const assert = require('node:assert/strict');
const rules = require('../src/services/operatingRules.service');
test('coding uses each weekday pair, weekends and configured holidays', () => {
  for (let day = 1; day <= 5; day++) {
    const date = `2026-09-${String(6 + day).padStart(2, '0')}`;
    for (let digit = 0; digit <= 9; digit++) {
      assert.equal(rules.codingRestricted(`ABC ${digit}`, date), [day * 2 - 1, day * 2 % 10].includes(digit));
      assert.equal(rules.codingRestricted(`ABC ${digit}`, date, true), false);
    }
  }
  assert.equal(rules.codingRestricted('ABC 1', '2026-09-12'), false);
  assert.equal(rules.codingRestricted('ABC 1', '2026-09-13'), false);
  assert.throws(() => rules.codingRestricted('NO PLATE', '2026-09-07'), /numeric ending/);
});
test('coding date switches at Manila midnight, not UTC midnight', () => {
  assert.equal(rules.manilaDate(new Date('2026-09-07T15:59:59Z')), '2026-09-07');
  assert.equal(rules.manilaDate(new Date('2026-09-07T16:00:00Z')), '2026-09-08');
});
test('loading warns at eight minutes and closes at ten without departing', () => {
  const trip = { operatingMode: 'terminal_queue', terminalQueueStatus: 'loading', terminalLoadingStartedAt: new Date('2026-09-07T00:00:00Z') };
  assert.equal(rules.loadingTiming(trip, new Date('2026-09-07T00:07:59Z')).loadingWarning, false);
  assert.equal(rules.loadingTiming(trip, new Date('2026-09-07T00:08:00Z')).loadingWarning, true);
  assert.equal(rules.loadingTiming(trip, new Date('2026-09-07T00:09:59Z')).departureRequired, false);
  assert.equal(rules.loadingTiming(trip, new Date('2026-09-07T00:10:00Z')).departureRequired, true);
  assert.equal(trip.terminalQueueStatus, 'loading');
  assert.deepEqual(rules.loadingTiming({ ...trip, operatingMode: 'route' }), {});
  assert.equal(rules.loadingTiming({ ...trip, terminalLoadingStartedAt: null }).departureRequired, true);
});
