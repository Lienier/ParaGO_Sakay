const { haversineMeters } = require('./geo');

const validPoint = point => Array.isArray(point?.coordinates) && point.coordinates.length === 2 &&
  point.coordinates.every(n => typeof n === 'number' && Number.isFinite(n)) &&
  Math.abs(point.coordinates[0]) <= 180 && Math.abs(point.coordinates[1]) <= 90;
// Coordinates identify a physical stop; a display name alone is not an identity.
const destinationKey = member => member.destinationLocation.coordinates.map(n => n.toFixed(6)).join(',');
const evaluateArrival = ({ members, observation, previous = {}, now = new Date() }) => {
  const reset = reason => ({ reason, state: { streamId: previous.streamId, sequence: previous.sequence, lastCapturedAt: previous.lastCapturedAt, observations: 0 }, reachedKey: null });
  const o = observation;
  if (!o?.streamId || !Number.isSafeInteger(o.sequence) || o.sequence < 1) return reset('unordered');
  const captured = new Date(o.capturedAt).getTime();
  const age = now.getTime() - captured;
  if (!Number.isFinite(age) || age < 0 || age > 15000) return reset('stale');
  if (typeof o.accuracyMeters !== 'number' || !Number.isFinite(o.accuracyMeters) || o.accuracyMeters < 0 || o.accuracyMeters > 30) return reset('accuracy');
  if (typeof o.speedMetersPerSecond !== 'number' || !Number.isFinite(o.speedMetersPerSecond) || o.speedMetersPerSecond < 0 || o.speedMetersPerSecond > 5 / 3.6) return reset('speed');
  const point = { coordinates: [o.longitude, o.latitude] };
  if (!validPoint(point)) return reset('coordinates');
  // Completed stops remain candidates: a dwell at the last stop never advances another stop.
  const destinations = members.filter(m => validPoint(m.destinationLocation)).map(m => ({
    key: destinationKey(m),
    distance: haversineMeters(o.latitude, o.longitude, m.destinationLocation.coordinates[1], m.destinationLocation.coordinates[0]),
  })).sort((a, b) => a.distance - b.distance || a.key.localeCompare(b.key));
  const nearest = destinations[0];
  if (!nearest || nearest.distance > 50) return reset('outside_destination');
  if (previous.streamId === o.streamId && (o.sequence <= previous.sequence || captured <= new Date(previous.lastCapturedAt).getTime())) {
    return { reason: 'repeated', state: previous, reachedKey: null };
  }
  if (previous.lastCapturedAt && captured <= new Date(previous.lastCapturedAt).getTime()) return { reason: 'reordered', state: previous, reachedKey: null };
  const continues = previous.observations > 0 && previous.streamId === o.streamId && previous.destinationKey === nearest.key &&
    captured - new Date(previous.lastCapturedAt).getTime() <= 15000;
  const state = {
    streamId: o.streamId, sequence: o.sequence, destinationKey: nearest.key,
    startedAt: continues ? previous.startedAt : new Date(captured),
    lastCapturedAt: new Date(captured), observations: continues ? previous.observations + 1 : 1,
  };
  return { reason: 'valid', state, reachedKey: state.observations >= 3 && captured - new Date(state.startedAt).getTime() >= 10000 ? nearest.key : null };
};
module.exports = { validPoint, destinationKey, evaluateArrival };
