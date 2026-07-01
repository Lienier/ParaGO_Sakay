const { boardingWindowMinutes } = require('../config/env');
const ApiError = require('../utils/apiError');
const { haversineMeters } = require('../utils/geo');
const PickupRequest = require('../models/pickupRequest');
const TripSession = require('../models/tripSession');
const RideSession = require('../models/rideSession');
const Driver = require('../models/driver');
const Jeepney = require('../models/jeepney');
const { publishNotification } = require('./notificationPublisher');
const {
  serializePickupRequest,
  serializeRideSession,
} = require('../utils/realtimePayloads');
const {
  canPassengerBoardPickupRequest,
} = require('./pickupFlow.service');
const {
  isTerminalPickupType,
  normalizeTerminalQueueStatus,
} = require('./hybridDispatch.service');

const ensureTripHasBoardingCapacity = async (trip) => {
  const jeepney = await Jeepney.findById(trip.jeepneyId).select('capacity');
  const seatCapacity = Number(jeepney?.capacity);
  const occupiedSeats = Number.isFinite(Number(trip.occupancyCount))
    ? Number(trip.occupancyCount)
    : 0;
  if (
    Number.isFinite(seatCapacity) &&
    seatCapacity > 0 &&
    occupiedSeats >= seatCapacity
  ) {
    throw new ApiError(409, 'Trip is already at full capacity');
  }
};

const syncTerminalQueueAfterBoarding = async ({ trip, pickupType, now }) => {
  if (!isTerminalPickupType(pickupType) || trip.operatingMode !== 'terminal_queue') {
    return;
  }

  const terminalRequests = await PickupRequest.find({
    tripSessionId: trip._id,
    pickupType: 'terminal',
    status: { $in: ['pending', 'acknowledged'] },
  }).select('status');
  const hasAcknowledged = terminalRequests.some(
    (request) => request.status === 'acknowledged'
  );
  trip.terminalQueueStatus = normalizeTerminalQueueStatus(
    hasAcknowledged ? 'loading' : 'waiting',
    { operatingMode: trip.operatingMode }
  );
  await trip.save();
  if (trip.driverId) {
    await Driver.findByIdAndUpdate(trip.driverId, {
      $set: {
        operatingMode: trip.operatingMode,
        terminalQueueStatus: trip.terminalQueueStatus,
        terminalCheckedInAt: trip.terminalCheckedInAt || trip.startedAt || now,
        terminalQueueNumber: trip.terminalQueueNumber,
        terminalStopRef: trip.terminalStopRef,
      },
    });
  }
};

const completeBoardingForPickupRequest = async ({
  pickupRequest,
  trip,
  passengerId,
  now = new Date(),
  boardingMethod = 'manual',
  allowExisting = false,
}) => {
  const existing = await RideSession.findOne({
    passengerId,
    tripSessionId: trip._id,
    status: { $in: ['waiting', 'onboard'] },
  });
  if (existing) {
    if (allowExisting) {
      return existing;
    }
    throw new ApiError(409, 'Passenger already has an active ride session for this trip');
  }

  await ensureTripHasBoardingCapacity(trip);

  const pickupType = pickupRequest.pickupType || 'roadside';
  const pickupReference = isTerminalPickupType(pickupType)
    ? pickupRequest.terminalLocation || pickupRequest.pickupLocation
    : pickupRequest.pickupLocation;
  if (!pickupReference?.coordinates?.length) {
    throw new ApiError(409, 'Pickup request is missing a valid boarding reference');
  }
  const [lngPickup, latPickup] = pickupReference.coordinates;

  const savedDestinationCoordinates = Array.isArray(
    pickupRequest.destinationLocation?.coordinates
  )
    ? pickupRequest.destinationLocation.coordinates
    : [];
  const resolvedDestinationLat = Number(savedDestinationCoordinates[1]);
  const resolvedDestinationLng = Number(savedDestinationCoordinates[0]);
  const normalizedDestinationStopRef = String(
    pickupRequest.destinationStopRef || ''
  ).trim();
  if (!normalizedDestinationStopRef) {
    throw new ApiError(409, 'Pickup request is missing a saved unload destination');
  }
  if (
    !Number.isFinite(resolvedDestinationLat) ||
    !Number.isFinite(resolvedDestinationLng)
  ) {
    throw new ApiError(409, 'Pickup request is missing valid unload destination coordinates');
  }

  const rideSession = await RideSession.create({
    passengerId,
    tripSessionId: trip._id,
    pickupRequestId: pickupRequest._id,
    pickupType,
    boardingMethod,
    boardingStopRef: String(
      pickupRequest.terminalStopRef ||
          pickupRequest.stopRef ||
          pickupRequest.fareSnapshot?.boardingStopRef ||
          ''
    ).trim(),
    boardingLocation: {
      type: 'Point',
      coordinates: [Number(lngPickup), Number(latPickup)],
    },
    destinationStopRef: normalizedDestinationStopRef,
    destinationLocation: {
      type: 'Point',
      coordinates: [resolvedDestinationLng, resolvedDestinationLat],
    },
    fareSnapshot: pickupRequest.fareSnapshot || undefined,
    status: 'onboard',
    boardedAt: now,
    canSendStopAlert: true,
  });

  pickupRequest.status = 'completed';
  await pickupRequest.save();
  await TripSession.findByIdAndUpdate(trip._id, {
    $inc: { occupancyCount: 1 },
  });
  await syncTerminalQueueAfterBoarding({ trip, pickupType, now });

  const tripDriver = trip.driverId
    ? await Driver.findById(trip.driverId).select('userId')
    : null;
  await publishNotification({
    userId: tripDriver?.userId,
    type: 'passenger_boarded',
    title:
      boardingMethod === 'auto_proximity'
        ? 'Passenger auto-boarded'
        : 'Passenger boarded',
    body: `Passenger boarded near ${
      pickupRequest.terminalStopRef ||
      pickupRequest.stopRef ||
      'the selected pickup point'
    }.`,
    payload: {
      requestId: pickupRequest._id.toString(),
      tripSessionId: trip._id.toString(),
      boardingMethod,
      request: serializePickupRequest(pickupRequest),
      rideSession: serializeRideSession(rideSession),
    },
    category: 'trip',
  });

  return rideSession;
};

const validateBoardingAttempt = async ({
  passengerId,
  tripSessionId,
  pickupRequestId,
  lat,
  lng,
  destinationStopRef,
  destinationLat,
  destinationLng,
}) => {
  const pickupRequest = await PickupRequest.findOne({
    _id: pickupRequestId,
    passengerId,
    tripSessionId,
  });
  if (!pickupRequest) {
    throw new ApiError(404, 'No matching pickup request found');
  }
  const pickupType = pickupRequest.pickupType || 'roadside';
  if (!canPassengerBoardPickupRequest(pickupRequest.status, { pickupType })) {
    throw new ApiError(
      409,
      'Pickup request must be acknowledged by the driver before boarding'
    );
  }

  const pickupReference = isTerminalPickupType(pickupType)
    ? pickupRequest.terminalLocation || pickupRequest.pickupLocation
    : pickupRequest.pickupLocation;
  if (!pickupReference?.coordinates?.length) {
    throw new ApiError(409, 'Pickup request is missing a valid boarding reference');
  }

  const now = new Date();
  if (pickupRequest.expiresAt && now > new Date(pickupRequest.expiresAt)) {
    pickupRequest.status = 'expired';
    await pickupRequest.save();
    throw new ApiError(409, 'Pickup request expired');
  }

  const trip = await TripSession.findById(tripSessionId);
  if (!trip || trip.status !== 'active') {
    throw new ApiError(409, 'Trip session is not active');
  }

  if (
    boardingWindowMinutes &&
    now.getTime() - new Date(pickupRequest.createdAt).getTime() > boardingWindowMinutes * 60_000
  ) {
    throw new ApiError(409, 'Boarding attempt outside allowed time window');
  }

  const [lngPickup, latPickup] = pickupReference.coordinates;
  const hasClientLocation = lat != null && lng != null;
  const compareLat = hasClientLocation ? Number(lat) : latPickup;
  const compareLng = hasClientLocation ? Number(lng) : lngPickup;
  if (
    !Number.isFinite(compareLat) ||
    compareLat < -90 ||
    compareLat > 90 ||
    !Number.isFinite(compareLng) ||
    compareLng < -180 ||
    compareLng > 180
  ) {
    throw new ApiError(400, 'Invalid boarding location coordinates');
  }

  const distance = haversineMeters(compareLat, compareLng, latPickup, lngPickup);
  // 250m default grace distance for realistic boarding check
  if (distance > 250) {
    throw new ApiError(409, 'Boarding request too far from pickup area');
  }

  if (destinationStopRef || destinationLat != null || destinationLng != null) {
    pickupRequest.destinationStopRef =
      String(destinationStopRef || pickupRequest.destinationStopRef || '').trim();
    pickupRequest.destinationLocation = {
      type: 'Point',
      coordinates: [
        destinationLng != null ? Number(destinationLng) : Number(pickupRequest.destinationLocation?.coordinates?.[0]),
        destinationLat != null ? Number(destinationLat) : Number(pickupRequest.destinationLocation?.coordinates?.[1]),
      ],
    };
  }

  return completeBoardingForPickupRequest({
    passengerId,
    trip,
    pickupRequest,
    now,
    boardingMethod: 'manual',
  });
};

module.exports = {
  completeBoardingForPickupRequest,
  validateBoardingAttempt,
};
