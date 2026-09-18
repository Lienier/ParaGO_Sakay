const Passenger = require('../models/passenger');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');

function validate(body = {}) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new ApiError(400, 'Invalid saved place');
  const name = typeof body.name === 'string' ? body.name.trim().replace(/\s+/g, ' ') : '';
  if (!name || name.length > 60 || /[\x00-\x1f\x7f]/.test(name)) throw new ApiError(400, 'Place name must contain 1–60 characters');
  if (typeof body.lat !== 'number' || !Number.isFinite(body.lat) || Math.abs(body.lat) > 90 ||
      typeof body.lng !== 'number' || !Number.isFinite(body.lng) || Math.abs(body.lng) > 180) {
    throw new ApiError(400, 'A valid location is required');
  }
  return { name, key: name.toLowerCase(), lat: body.lat, lng: body.lng };
}
async function list(userId) {
  const passenger = await Passenger.findOne({ userId }).select('savedPlaces').lean();
  if (!passenger) throw new ApiError(404, 'Passenger profile missing');
  return passenger.savedPlaces || [];
}
async function add(userId, body) {
  const place = validate(body);
  // One document update makes both the name check and size limit atomic.
  const result = await Passenger.findOneAndUpdate({ userId,
    'savedPlaces.key': { $ne: place.key }, 'savedPlaces.19': { $exists: false },
  }, { $push: { savedPlaces: place } }, { new: true, runValidators: true }).select('savedPlaces');
  if (result) return result.savedPlaces;
  const places = await list(userId);
  const existing = places.find(p => p.key === place.key);
  // A retry after a lost response must not create another place.
  if (existing && existing.lat === place.lat && existing.lng === place.lng) return places;
  throw new ApiError(409, existing ? 'That place name already exists. Choose another name.' : 'You can save up to 20 places. Remove one first.');
}
async function remove(userId, id) {
  ensureObjectId(id, 'place ID');
  const result = await Passenger.findOneAndUpdate({ userId }, { $pull: { savedPlaces: { _id: id } } }, { new: true }).select('savedPlaces');
  if (!result) throw new ApiError(404, 'Passenger profile missing');
  return result.savedPlaces;
}
module.exports = { list, add, remove, validate };
