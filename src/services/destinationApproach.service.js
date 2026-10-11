const Passenger = require('../models/passenger');
const RideSession = require('../models/rideSession');
const { destinationApproachAlertMeters } = require('../config/env');
const {
  buildDestinationApproachPayload,
  hasValidDestinationPoint,
  isRideWithinDestinationApproachThreshold,
} = require('../utils/destinationApproach');
const { publishNotification } = require('./notificationPublisher');

const unresolvedDestinationApproachQuery = {
  $or: [
    { destinationApproachAlertedAt: { $exists: false } },
    { destinationApproachAlertedAt: null },
  ],
};

const publishDestinationApproachNotifications = async ({
  ride,
  driverUserId,
  thresholdMeters,
  triggeredAt,
}) => {
  const passenger = await Passenger.findById(ride.passengerId).select('userId');
  const stopLabel =
    String(ride.destinationStopRef || '').trim() || 'the saved destination';
  const payload = buildDestinationApproachPayload({
    ride,
    thresholdMeters,
    triggeredAt,
  });

  await Promise.all([
    publishNotification({
      userId: driverUserId,
      type: 'passenger_near_destination',
      title: 'Passenger nearing destination',
      body: `A passenger is nearing ${stopLabel}.`,
      payload,
      category: 'ride',
    }),
    publishNotification({
      userId: passenger?.userId,
      type: 'passenger_near_destination',
      title: 'You are nearing your destination',
      body: `You are within ${thresholdMeters} meters of ${stopLabel}. The driver has been notified.`,
      payload,
      category: 'ride',
    }),
  ]);
};

const processDestinationApproachAlerts = async ({
  tripSessionId,
  driverUserId,
  latitude,
  longitude,
  previousLatitude,
  previousLongitude,
}) => {
  const thresholdMeters = Number(destinationApproachAlertMeters);
  if (
    !tripSessionId ||
    !driverUserId ||
    !Number.isFinite(Number(latitude)) ||
    !Number.isFinite(Number(longitude)) ||
    !Number.isFinite(thresholdMeters)
  ) {
    return [];
  }

  const rides = await RideSession.find({
    tripSessionId,
    status: 'onboard',
    flowVersion: { $ne: 2 },
    'destinationLocation.coordinates.1': { $exists: true },
    ...unresolvedDestinationApproachQuery,
  }).select('passengerId tripSessionId destinationStopRef destinationLocation');

  const notifiedRideIds = [];
  for (const ride of rides) {
    if (!hasValidDestinationPoint(ride)) {
      continue;
    }
    if (
      !isRideWithinDestinationApproachThreshold({
        ride,
        latitude,
        longitude,
        thresholdMeters,
        previousLatitude,
        previousLongitude,
      })
    ) {
      continue;
    }

    const triggeredAt = new Date();
    const claimedRide = await RideSession.findOneAndUpdate(
      {
        _id: ride._id,
        status: 'onboard',
        ...unresolvedDestinationApproachQuery,
      },
      {
        $set: {
          destinationApproachAlertedAt: triggeredAt,
        },
      },
      {
        new: true,
      }
    ).select('passengerId tripSessionId destinationStopRef destinationLocation');

    if (!claimedRide) {
      continue;
    }

    try { await publishDestinationApproachNotifications({
      ride: claimedRide,
      driverUserId,
      thresholdMeters,
      triggeredAt,
    });
    } catch (_) { console.error('[Destination approach] Notification failed after claim'); }
    notifiedRideIds.push(claimedRide._id.toString());
  }

  const groups = await RideSession.find({ tripSessionId, flowVersion: 2, status: 'onboard' });
  for (const ride of groups) {
    const destinations = new Set();
    for (const member of ride.members.filter(m => m.status === 'onboard' && !m.approachAlertedAt)) {
      const key = require('../utils/destinationArrival').destinationKey(member);
      if (destinations.has(key)) continue;
      destinations.add(key);
      const memberRide = { ...ride.toObject(), destinationLocation: member.destinationLocation, destinationStopRef: member.destinationStopRef };
      if (!isRideWithinDestinationApproachThreshold({ ride: memberRide, latitude, longitude, thresholdMeters, previousLatitude, previousLongitude })) continue;
      const triggeredAt = new Date();
      const updated = await RideSession.findOneAndUpdate({ _id: ride._id, status: 'onboard', members: { $elemMatch: { memberId: member.memberId, approachAlertedAt: null, status: 'onboard' } } },
        { $set: { 'members.$[member].approachAlertedAt': triggeredAt } }, { new: true, arrayFilters: [{ 'member.destinationLocation.coordinates': member.destinationLocation.coordinates, 'member.status': 'onboard' }] });
      if (updated) {
        try { await publishDestinationApproachNotifications({ ride: memberRide, driverUserId, thresholdMeters, triggeredAt }); }
        catch (_) { console.error('[Destination approach] Notification failed after claim'); }
      }
    }
  }
  return notifiedRideIds;
};

module.exports = {
  processDestinationApproachAlerts,
  publishDestinationApproachNotifications,
};
