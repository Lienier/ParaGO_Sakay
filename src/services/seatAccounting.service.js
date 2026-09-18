const ApiError = require('../utils/apiError');
function partySize(value = 1) {
  if (!Number.isSafeInteger(value) || value < 1) throw new ApiError(400, 'Select a whole number of passengers, including yourself.', [], 'INVALID_PARTY_SIZE');
  return value;
}
async function sumSeats(Model, filter, field, session = null) {
  const rows = await Model.find(filter).select(`${field} status`).session(session).lean();
  return rows.reduce((sum, row) => sum + (row[field] ?? (field === 'remainingCount' && row.status === 'completed' ? 0 : 1)), 0);
}
async function counts(trip, session = null) {
  const Ride = require('../models/rideSession');
  const Pickup = require('../models/pickupRequest');
  const onboard = await sumSeats(Ride, { tripSessionId: trip._id, status: { $in: ['waiting', 'onboard'] } }, 'remainingCount', session);
  const reserved = await sumSeats(Pickup, { tripSessionId: trip._id, status: { $in: ['pending', 'acknowledged'] }, expiresAt: { $gt: new Date() } }, 'partySize', session);
  const occupied = Math.max(trip.occupancyCount || 0, onboard + (trip.manualOccupancyCount || 0));
  return { onboard, reserved, occupied };
}
async function assertCapacity(trip, size, session = null) {
  const vehicle = await require('../models/jeepney').findById(trip.jeepneyId).session(session);
  const { occupied, reserved } = await counts(trip, session);
  if (!vehicle || !Number.isFinite(vehicle.capacity) || occupied + reserved + size > vehicle.capacity) {
    throw new ApiError(409, 'This jeep does not have enough seats for your whole group. Refresh and try another jeep.', [], 'INSUFFICIENT_SEATS');
  }
}
module.exports = { partySize, sumSeats, counts, assertCapacity };
