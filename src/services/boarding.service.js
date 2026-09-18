const mongoose = require('mongoose');
const { boardingWindowMinutes, autoBoardingProximityMeters, autoBoardingPassengerLocationMaxAgeSeconds, autoBoardingDriverLocationMaxAgeSeconds } = require('../config/env');
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

const ensureTripHasBoardingCapacity = async (trip, { session, count = 1 } = {}) => {
  const jeepney = await Jeepney.findById(trip.jeepneyId)
    .select('capacity')
    .session(session || null);
  const seatCapacity = Number(jeepney?.capacity);
  const occupiedSeats = Number.isFinite(Number(trip.occupancyCount))
    ? Number(trip.occupancyCount)
    : 0;
  if (
    Number.isFinite(seatCapacity) &&
    seatCapacity > 0 &&
    occupiedSeats + count > seatCapacity
  ) {
    throw new ApiError(409, 'Trip is already at full capacity');
  }
};

const isDuplicateKeyError = (error) => error?.code === 11000;

const syncTerminalQueueAfterBoarding = async () => {};

const completeBoardingForPickupRequest = async ({
  pickupRequest,
  trip,
  passengerId,
  now = new Date(),
  boardingMethod = 'manual',
  allowExisting = false,
  groupConfirmation = null,
}) => {
  const size = pickupRequest.partySize ?? 1;
  if (size > 1 && !groupConfirmation) throw new ApiError(409, 'Your driver must confirm how many people boarded.', [], 'GROUP_CONFIRMATION_REQUIRED');
  const count = groupConfirmation?.count ?? 1;
  if (!Number.isSafeInteger(count) || count < 1 || count > size) throw new ApiError(400, 'Boarded count must be between one and your reserved seats.', [], 'INVALID_BOARDING_COUNT');
  if (groupConfirmation && (typeof groupConfirmation.requestId !== 'string' || !/^[a-zA-Z0-9-]{8,80}$/.test(groupConfirmation.requestId))) throw new ApiError(400, 'A valid action reference is required. Refresh and try again.');
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

  const rideDocument = {
    partySize: size, boardedCount: count, remainingCount: count,
    regularTotal: Math.round((pickupRequest.fareSnapshot?.amount || 0) * count * 100) / 100,
    boardingMutationId: groupConfirmation?.requestId,
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
  };

  const session = await mongoose.startSession();
  let rideSession;
  let created = false;
  try {
    await session.withTransaction(async () => {
      created = false;
      if (pickupType === 'terminal') await require('./terminalQueue.service').lock(trip.routeId, session);
      await require('./passengerJourney.service').lockPassenger(passengerId, session);
      if (groupConfirmation) {
        const driver = await Driver.findOne({ userId: groupConfirmation.driverUserId, status: 'active' }).session(session);
        const assigned = driver && await TripSession.findOne({ _id: trip._id, driverId: driver._id }).session(session);
        if (!assigned) throw new ApiError(403, 'You are not assigned to this group booking.');
      }
      const exactExisting = await RideSession.findOne({
        pickupRequestId: pickupRequest._id,
      }).session(session);
      if (exactExisting) {
        if (groupConfirmation && exactExisting.boardedCount !== count) throw new ApiError(409, 'Boarding was already confirmed with a different count. Refresh the ride.', [], 'BOARDING_COUNT_CONFLICT');
        rideSession = exactExisting;
        return;
      }

      const activeExisting = await RideSession.findOne({
        passengerId,
        status: { $in: ['waiting', 'onboard'] },
      }).session(session);
      if (activeExisting) {
        if (allowExisting && String(activeExisting.pickupRequestId) === String(pickupRequest._id)) {
          rideSession = activeExisting;
          return;
        }
        throw new ApiError(
          409,
          'Passenger already has an active ride session'
        );
      }

      const freshPickup = await PickupRequest.findOne({
        _id: pickupRequest._id,
        passengerId,
        tripSessionId: trip._id,
        status: { $in: ['pending', 'acknowledged'] },
      }).session(session);
      if (!freshPickup) {
        throw new ApiError(409, 'Pickup request is no longer available for boarding');
      }
      if (groupConfirmation && (!freshPickup.groupReadyAt || freshPickup.status !== 'acknowledged' || (freshPickup.partySize ?? 1) !== size)) {
        throw new ApiError(409, 'The organizer must confirm the group is near the jeep before you confirm boarding.', [], 'GROUP_NOT_READY');
      }

      const freshTrip = await TripSession.findOne({
        _id: trip._id,
        status: 'active',
      }).session(session);
      if (!freshTrip) {
        throw new ApiError(409, 'Trip session is not active');
      }
      const checkedAt = new Date();
      if (freshPickup.expiresAt && checkedAt >= freshPickup.expiresAt) {
        throw new ApiError(409, 'Pickup request expired');
      }
      if (boardingMethod === 'manual' && boardingWindowMinutes &&
          checkedAt - freshPickup.createdAt > boardingWindowMinutes * 60000) {
        throw new ApiError(409, 'Boarding attempt outside allowed time window');
      }
      if (boardingMethod === 'manual' && pickupType !== 'terminal') {
        const passenger = await require('../models/passenger').findById(passengerId).session(session);
        const vehicle = await Jeepney.findById(freshTrip.jeepneyId).session(session);
        const age = (date) => date ? checkedAt - new Date(date) : Infinity;
        const p = passenger?.lastKnownLocation?.coordinates;
        const v = vehicle?.lastKnownLocation?.coordinates;
        if (age(passenger?.lastSeenAt) < 0 || age(passenger?.lastSeenAt) > autoBoardingPassengerLocationMaxAgeSeconds * 1000 ||
            age(vehicle?.lastSeenAt) < 0 || age(vehicle?.lastSeenAt) > autoBoardingDriverLocationMaxAgeSeconds * 1000 ||
            p?.length !== 2 || v?.length !== 2) {
          throw new ApiError(409, 'Fresh passenger and driver GPS are required. Refresh location and try again');
        }
        if (haversineMeters(p[1], p[0], v[1], v[0]) > autoBoardingProximityMeters) {
          throw new ApiError(409, 'Move near your assigned jeep before confirming boarding');
        }
      }
      if (pickupType === 'terminal') {
        if (boardingMethod !== 'manual' || freshTrip.operatingMode !== 'terminal_queue' || freshTrip.terminalQueueStatus !== 'loading')
          throw new ApiError(409, 'Only the assigned loading jeep accepts terminal boarding');
        const passenger = await require('../models/passenger').findById(passengerId).session(session);
        const vehicle = await Jeepney.findById(freshTrip.jeepneyId).session(session);
        const fresh = (date, seconds) => date && Date.now() - new Date(date).getTime() >= 0 && Date.now() - new Date(date).getTime() <= seconds * 1000;
        const p = passenger?.lastKnownLocation?.coordinates; const v = vehicle?.lastKnownLocation?.coordinates;
        if (!fresh(passenger?.lastSeenAt, autoBoardingPassengerLocationMaxAgeSeconds) || !fresh(vehicle?.lastSeenAt, autoBoardingDriverLocationMaxAgeSeconds) || p?.length !== 2 || v?.length !== 2)
          throw new ApiError(409, 'Fresh passenger and driver GPS are required. Refresh location and try again');
        if (haversineMeters(p[1], p[0], v[1], v[0]) > autoBoardingProximityMeters)
          throw new ApiError(409, 'Move near your assigned jeep before confirming boarding');
      }
      await ensureTripHasBoardingCapacity(freshTrip, { session, count });

      [rideSession] = await RideSession.create([rideDocument], { session });
      await PickupRequest.updateOne(
        { _id: pickupRequest._id },
        {
          $set: {
            status: 'completed',
            destinationStopRef: normalizedDestinationStopRef,
            destinationLocation: {
              type: 'Point',
              coordinates: [resolvedDestinationLng, resolvedDestinationLat],
            },
          },
        },
        { session }
      );
      await TripSession.updateOne(
        { _id: trip._id },
        { $inc: { occupancyCount: count } },
        { session }
      );
      created = true;
    });
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      rideSession = await RideSession.findOne({
        pickupRequestId: pickupRequest._id,
      });
      if (rideSession) {
        created = false;
      } else {
        throw error;
      }
    } else {
      throw error;
    }
  } finally {
    await session.endSession();
  }

  if (!rideSession) {
    throw new ApiError(409, 'Boarding could not be completed safely');
  }
  if (!created) {
    return rideSession;
  }

  pickupRequest.status = 'completed';
  // Notify the owner independently: driver delivery must not gate passenger state.
  try {
    const passenger = await require('../models/passenger').findById(passengerId).select('userId');
    const savedRequest = await PickupRequest.findById(pickupRequest._id);
    await publishNotification({
      userId: passenger?.userId,
      type: 'pickup_request_completed',
      title: 'Boarding confirmed',
      body: 'You are now onboard your assigned jeep.',
      payload: {
        requestId: pickupRequest._id.toString(),
        tripSessionId: trip._id.toString(),
        boardingMethod,
        request: serializePickupRequest(savedRequest),
        rideSession: serializeRideSession(rideSession),
      },
      category: 'ride',
    });
  } catch (_) {
    console.error('[Boarding] Passenger notification failed after commit');
  }
  const updatedTrip = await TripSession.findById(trip._id);
  if (updatedTrip) {
    await syncTerminalQueueAfterBoarding({
      trip: updatedTrip,
      pickupType,
      now,
    });
  }

  const tripDriver = trip.driverId
    ? await Driver.findById(trip.driverId).select('userId')
    : null;
  try {
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
  } catch (error) {
    console.error('[Boarding] Notification publication failed:', error.message);
  }

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
  if (destinationStopRef || destinationLat != null || destinationLng != null) {
    const saved = pickupRequest.destinationLocation?.coordinates || [];
    if ((destinationStopRef && String(destinationStopRef).trim() !== pickupRequest.destinationStopRef) ||
        (destinationLat != null && Number(destinationLat) !== Number(saved[1])) ||
        (destinationLng != null && Number(destinationLng) !== Number(saved[0]))) {
      throw new ApiError(409, 'Boarding must use the booked destination and fare');
    }
  }

  // A lost response or GPS-triggered boarding must be safe to confirm again.
  const existingRide = await RideSession.findOne({ pickupRequestId, passengerId, tripSessionId });
  if (existingRide) return existingRide;
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
