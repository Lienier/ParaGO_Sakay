const ApiError = require('./apiError');

// Booking pins are independent of passenger GPS; boarding still verifies GPS.
function requireBookingPoint(point, label) {
  const coordinates = point?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length !== 2 ||
      coordinates.some(v => typeof v !== 'number' || !Number.isFinite(v)) ||
      Math.abs(coordinates[0]) > 180 || Math.abs(coordinates[1]) > 90) {
    throw new ApiError(400, `Choose a valid ${label} point on the selected route.`, [], 'INVALID_BOOKING_PIN');
  }
  return { type: 'Point', coordinates: [...coordinates] };
}
module.exports = { requireBookingPoint };
