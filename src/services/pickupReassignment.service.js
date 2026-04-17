const PickupRequest = require('../models/pickupRequest');
const TripSession = require('../models/tripSession');
const Passenger = require('../models/passenger');
const { haversineMeters } = require('../utils/geo');
const { jeepPassByReassignMeters } = require('../config/env');
const { publishNotification } = require('./notificationPublisher');
const Route = require('../models/route');
const { nearestRouteProjection } = require('../utils/routeGeo');

const pointCoordinates = (value) =>
  Array.isArray(value?.coordinates) && value.coordinates.length >= 2
    ? [Number(value.coordinates[0]), Number(value.coordinates[1])]
    : null;

/**
 * Check if assigned jeep has passed by the passenger's pickup location
 * Returns true if jeep is more than threshold meters past the pickup point
 */
const hasJeepPassedBy = ({ route, jeepLocation, pickupLocation, threshold }) => {
  const jeepCoords = pointCoordinates(jeepLocation);
  const pickupCoords = pointCoordinates(pickupLocation);

  if (!route || !jeepCoords || !pickupCoords) {
    return false;
  }

  const jeepProjection = nearestRouteProjection({
    latitude: jeepCoords[1],
    longitude: jeepCoords[0],
    route,
  });
  const pickupProjection = nearestRouteProjection({
    latitude: pickupCoords[1],
    longitude: pickupCoords[0],
    route,
  });
  if (!jeepProjection || !pickupProjection) {
    return false;
  }

  const distance = haversineMeters(
    pickupCoords[1],
    pickupCoords[0],
    jeepCoords[1],
    jeepCoords[0]
  );

  return jeepProjection.progress > pickupProjection.progress && distance > threshold;
};

/**
 * Check pending pickup requests and reassign if jeep has passed by
 */
const checkAndReassignPassedRequests = async () => {
  try {
    // Find all pending or acknowledged requests
    const pendingRequests = await PickupRequest.find({
      status: { $in: ['pending', 'acknowledged'] },
      expiresAt: { $gt: new Date() },
    }).populate('tripSessionId');

    for (const request of pendingRequests) {
      if (!request.tripSessionId) continue;

      const trip = await TripSession.findById(request.tripSessionId)
        .populate('jeepneyId', 'lastKnownLocation')
        .populate('driverId', 'userId');

      if (!trip || trip.status !== 'active' || !trip.jeepneyId) continue;
      const route = await Route.findById(trip.routeId);
      if (!route) continue;

      // Check if jeep has passed by the pickup location
      const hasPassed = hasJeepPassedBy({
        route,
        jeepLocation: trip.jeepneyId.lastKnownLocation,
        pickupLocation: request.pickupLocation,
        threshold: jeepPassByReassignMeters,
      });

      if (hasPassed) {
        // Mark current request as expired
        request.status = 'expired';
        await request.save();

        // Notify passenger that jeep passed by
        const passenger = await Passenger.findById(request.passengerId).select('userId');
        await publishNotification({
          userId: passenger?.userId,
          type: 'pickup_request_expired',
          title: 'Jeepney passed by',
          body: 'The assigned jeepney has passed your pickup location. Please send a new pickup request.',
          payload: {
            requestId: request._id.toString(),
            tripSessionId: trip._id.toString(),
            reason: 'jeep_passed_by',
          },
          category: 'trip',
        });

        // Notify driver that request was auto-cancelled
        await publishNotification({
          userId: trip.driverId?.userId,
          type: 'pickup_request_auto_cancelled',
          title: 'Pickup request auto-cancelled',
          body: 'Pickup request was automatically cancelled as you passed the pickup location.',
          payload: {
            requestId: request._id.toString(),
            tripSessionId: trip._id.toString(),
            reason: 'jeep_passed_by',
          },
          category: 'trip',
        });

        console.log(`[Reassignment] Request ${request._id} expired - jeep passed by`);
      }
    }
  } catch (error) {
    console.error('[Reassignment Service] Error checking passed requests:', error);
  }
};

module.exports = {
  hasJeepPassedBy,
  checkAndReassignPassedRequests,
};
