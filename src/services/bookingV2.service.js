const crypto = require('crypto');
const ApiError = require('../utils/apiError');
const { requireBookingPoint } = require('../utils/bookingLocation');
const { isRoutePickupNearRoad, isPointAfterOnRoute, resolveRouteFareSnapshot } = require('../utils/routeGeo');
const { normalizePickupType, resolveRouteTerminalStop } = require('./hybridDispatch.service');

function quoteBooking(route, payload) {
  const config = require('../config/env');
  const pickupType = normalizePickupType(payload.pickupType);
  const terminal = pickupType === 'terminal' ? resolveRouteTerminalStop(route) : null;
  if (pickupType === 'terminal' && !terminal) throw new ApiError(409, 'This route has no terminal configured.');
  const pickupLocation = requireBookingPoint(terminal?.location || payload.pickupLocation, 'pickup');
  if (!isRoutePickupNearRoad({ route, longitude: pickupLocation.coordinates[0], latitude: pickupLocation.coordinates[1], maxDistanceMeters: config.pickupRoadProximityMeters })) throw new ApiError(400, 'Move the pickup point onto the selected route.');
  if (!Array.isArray(payload.members) || payload.members.length < 1 || payload.members.length > 100) throw new ApiError(400, 'Choose a destination for each passenger, including you.');
  const members = payload.members.map((member, i) => {
    const destinationLocation = requireBookingPoint(member.destinationLocation, `Passenger ${i + 1} drop-off`);
    const destinationStopRef = typeof member.destinationStopRef === 'string' ? member.destinationStopRef.trim().slice(0, 512) : '';
    if (!destinationStopRef) throw new ApiError(400, 'Every drop-off needs a name.');
    const [lng, lat] = destinationLocation.coordinates;
    if (!isRoutePickupNearRoad({ route, longitude: lng, latitude: lat, maxDistanceMeters: config.unloadRoadProximityMeters })) throw new ApiError(400, 'Every drop-off must be on the selected route.', [], 'DESTINATION_OFF_ROUTE');
    if (!isPointAfterOnRoute({ route, startLongitude: pickupLocation.coordinates[0], startLatitude: pickupLocation.coordinates[1], endLongitude: lng, endLatitude: lat })) throw new ApiError(400, 'Every drop-off must be after the pickup.', [], 'DESTINATION_BEFORE_PICKUP');
    return { memberId: `member-${i + 1}`, organizer: i === 0, label: i === 0 ? 'You' : `Passenger ${i + 1}`,
      destinationStopRef, destinationLocation, status: 'reserved',
      fareSnapshot: resolveRouteFareSnapshot({ route, pickupLocation, destinationLocation }) };
  });
  const regularTotal = Math.round(members.reduce((sum, m) => sum + m.fareSnapshot.amount, 0) * 100) / 100;
  const quoteToken = crypto.createHash('sha256').update(JSON.stringify({ routeId: String(route._id), pickupType, pickupLocation, members, regularTotal })).digest('hex');
  return { flowVersion: 2, members, partySize: members.length, regularTotal, quoteToken, pickupType, pickupLocation, terminal };
}
function requireReviewedQuote(quote, payload) {
  if (payload.quoteToken !== quote.quoteToken) throw new ApiError(409, 'Prices or destinations changed. Review the updated quote before booking.', [quote], 'QUOTE_REVIEW_REQUIRED');
}
module.exports = { quoteBooking, requireReviewedQuote };
