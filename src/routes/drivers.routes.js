const express = require('express');
const Driver = require('../models/driver');
const TripSession = require('../models/tripSession');
const Jeepney = require('../models/jeepney');
const asyncHandler = require('../utils/asyncHandler');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const { DRIVER } = require('../constants/roles');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');
const { ensureLatLng } = require('../utils/validators');
const { hasOwn } = require('../utils/object');
const { asyncLocationProcessingEnabled } = require('../config/env');
const { requireCurrentDriver } = require('../services/routeContext.service');
const {
  processDestinationApproachAlerts,
} = require('../services/destinationApproach.service');
const {
  processAutomaticBoardingForTrip,
} = require('../services/automaticBoarding.service');
const {
  processAutomaticOffboardingForTrip,
} = require('../services/automaticOffboarding.service');
const { emitJeepneyLocationUpdate } = require('../realtime/socketServer');
const {
  validateOrderedLocationPayload,
  buildPersistentLocationOrderFilter,
  persistentLocationOrderUpdate,
  stalePersistentLocationError,
  rememberPersistedDriverLocationOrder,
  reserveDriverLocationOrder,
  hasDriverLocationOrderingState,
} = require('../services/driverLocationOrdering.service');
const {
  resolveDriverActiveContext,
  invalidateDriverActiveContext,
} = require('../services/activeDriverContext.service');
const {
  cacheLatestJeepLocation,
  getLatestJeepLocation,
} = require('../services/transientState.service');
const { getRedisHealth } = require('../services/redis.service');
const {
  enqueueLocationWork,
  enqueueAutomationWork,
} = require('../services/asyncJobQueue.service');
const { apiRateLimiters } = require('../middlewares/rateLimits');
const {
  presentLicenseDocuments,
} = require('../services/driverLicenseDocuments.service');
const {
  processTerminalArrival,
} = require('../services/terminalArrival.service');
const {
  normalizeLicenseNumber,
  validateCpNumber,
  validateLicenseNumber,
} = require('../utils/driverIdentity');

const router = express.Router();

router.get(
  '/me',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const profile = await requireCurrentDriver(req.user, {
      populate: {
        path: 'userId',
        select: 'status email fullName phone',
      },
    });
    const raw =
      typeof profile.toObject === 'function' ? profile.toObject() : profile;
    return ok(
      res,
      {
        ...raw,
        accountStatus: profile.userId?.status?.toString() ?? req.user.status ?? 'unknown',
      },
      'Driver profile'
    );
  })
);

router.get(
  '/me/license-documents',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const profile = await Driver.findOne({ userId: req.user._id }).select(
      '+licenseDocuments'
    );
    if (!profile) throw new ApiError(404, 'Driver record missing');
    return ok(
      res,
      await presentLicenseDocuments(profile.licenseDocuments),
      'Driver license documents'
    );
  })
);

const updateDriverStatus = async (req, res) => {
  const status = String(req.body?.status || '').toLowerCase();
  if (!['active', 'inactive'].includes(status)) {
    throw new ApiError(400, 'status must be one of: active, inactive');
  }
  let profile = await Driver.findOneAndUpdate(
    { userId: req.user._id },
    { $set: { status } },
    { new: true }
  );
  if (!profile) {
    profile = await Driver.create({
      userId: req.user._id,
      status,
    });
  }
  await invalidateDriverActiveContext(profile._id);
  return ok(res, { status: profile.status }, 'Driver status updated');
};

for (const method of ['patch', 'post', 'put']) {
  router[method](
    '/me/status',
    authenticate,
    authorize(DRIVER),
    asyncHandler(updateDriverStatus)
  );
}

router.get(
  '/me/active-trips',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const driver = await requireCurrentDriver(req.user, {
      notFoundMessage: 'Driver record missing',
    });
    const trips = await TripSession.find({
      driverId: driver._id,
      status: { $in: ['active', 'scheduled'] },
    });
    return ok(res, trips, 'Driver active/scheduled trips');
  })
);

router.put(
  '/me',
  authenticate,
  authorize(DRIVER),
  asyncHandler(async (req, res) => {
    const updates = {};
    if (hasOwn(req.body, 'licenseNumber')) {
      const licenseNumber = validateLicenseNumber(req.body.licenseNumber);
      updates.licenseNumber = licenseNumber;
      updates.licenseNumberNormalized = normalizeLicenseNumber(licenseNumber);
    }
    if (hasOwn(req.body, 'employeeNumber')) {
      updates.employeeNumber = String(req.body.employeeNumber || '').trim();
    }
    if (hasOwn(req.body, 'phone')) {
      updates.phone = validateCpNumber(req.body.phone);
    }
    if (!Object.keys(updates).length) {
      throw new ApiError(400, 'No valid driver profile fields provided');
    }

    let profile;
    try {
      profile = await Driver.findOneAndUpdate(
        { userId: req.user._id },
        { $set: updates },
        { new: true, upsert: true, setDefaultsOnInsert: true }
      );
    } catch (error) {
      if (error.code === 11000 && error.keyPattern?.licenseNumberNormalized) {
        throw new ApiError(409, 'License number already belongs to another driver');
      }
      throw error;
    }
    return ok(res, profile, 'Driver profile updated');
  })
);

const updateDriverJeepneyLocation = async (req, res) => {
  const body = req.body || {};
  const usesOrderedProtocol =
    body.streamId != null ||
    body.sequence != null ||
    body.capturedAt != null ||
    body.latitude != null ||
    body.longitude != null;
  const serverReceivedAt = new Date();
  const orderedLocation = usesOrderedProtocol
    ? validateOrderedLocationPayload(body, serverReceivedAt)
    : null;
  const latitude = orderedLocation?.latitude ?? Number(body.lat);
  const longitude = orderedLocation?.longitude ?? Number(body.lng);
  ensureLatLng(latitude, longitude, 'location');

  const driver = await requireCurrentDriver(req.user);

  const activeContext = await resolveDriverActiveContext(driver);
  const jeepneyId = activeContext.value?.jeepneyId;
  if (!jeepneyId) {
    throw new ApiError(
      404,
      'No jeepney found for this driver. Set a jeepney assignment first.'
    );
  }

  const acknowledgement = {
    accepted: true,
    streamId: orderedLocation?.streamId || 'legacy',
    sequence: orderedLocation?.sequence ?? null,
    serverReceivedAt: serverReceivedAt.toISOString(),
  };

  const activeTrip =
    activeContext.value?.tripStatus === 'active' &&
    activeContext.value?.tripId
      ? {
          _id: activeContext.value.tripId,
          routeId: activeContext.value.routeId,
        }
      : await TripSession.findOne({
          jeepneyId,
          status: 'active',
        }).select('_id routeId');

  if (orderedLocation) {
    await processTerminalArrival({
      actor: req.user,
      jeepneyId,
      latitude,
      longitude,
      accuracyMeters: orderedLocation.accuracyMeters,
      streamId: orderedLocation.streamId,
      sequence: orderedLocation.sequence,
      capturedAt: orderedLocation.capturedAt,
      now: serverReceivedAt,
    });
  }

  if (
    asyncLocationProcessingEnabled &&
    orderedLocation &&
    getRedisHealth().status === 'healthy'
  ) {
    let persistedState = null;
    if (!hasDriverLocationOrderingState(jeepneyId)) {
      persistedState = await Jeepney.findById(jeepneyId).select(
        'lastKnownLocation latestLocationOrder'
      );
      const persistedOrder = persistedState?.latestLocationOrder;
      if (
        persistedOrder?.streamId &&
        Number.isSafeInteger(Number(persistedOrder.sequence)) &&
        persistedOrder.capturedAt &&
        persistedOrder.serverReceivedAt
      ) {
        rememberPersistedDriverLocationOrder({
          jeepneyId,
          streamId: persistedOrder.streamId,
          sequence: Number(persistedOrder.sequence),
          capturedAt: new Date(persistedOrder.capturedAt),
          serverReceivedAt: new Date(persistedOrder.serverReceivedAt),
        });
      }
    }
    reserveDriverLocationOrder({
      jeepneyId,
      streamId: orderedLocation.streamId,
      sequence: orderedLocation.sequence,
      capturedAt: orderedLocation.capturedAt,
      serverReceivedAt,
    });

    const cachedPrevious = await getLatestJeepLocation(jeepneyId);
    const persistedCoordinates = Array.isArray(
      persistedState?.lastKnownLocation?.coordinates
    )
      ? persistedState.lastKnownLocation.coordinates
      : [];
    const previousLatitude = Number.isFinite(
      Number(cachedPrevious.value?.latitude)
    )
      ? Number(cachedPrevious.value.latitude)
      : persistedCoordinates.length >= 2
        ? Number(persistedCoordinates[1])
        : null;
    const previousLongitude = Number.isFinite(
      Number(cachedPrevious.value?.longitude)
    )
      ? Number(cachedPrevious.value.longitude)
      : persistedCoordinates.length >= 2
        ? Number(persistedCoordinates[0])
        : null;
    const idempotencyKey = `${jeepneyId}:${orderedLocation.streamId}:${orderedLocation.sequence}`;
    const job = {
      idempotencyKey,
      jeepneyId: jeepneyId.toString(),
      tripId: activeTrip?._id?.toString() || null,
      routeId: activeTrip?.routeId?.toString() || null,
      driverUserId: req.user._id.toString(),
      latitude,
      longitude,
      previousLatitude,
      previousLongitude,
      accuracyMeters: orderedLocation.accuracyMeters,
      speedMetersPerSecond: orderedLocation.speedMetersPerSecond,
      headingDegrees: orderedLocation.headingDegrees,
      streamId: orderedLocation.streamId,
      sequence: orderedLocation.sequence,
      capturedAt: orderedLocation.capturedAt.toISOString(),
      serverReceivedAt: serverReceivedAt.toISOString(),
      queuedAt: serverReceivedAt.toISOString(),
    };
    const cached = await cacheLatestJeepLocation({
      jeepneyId,
      latitude,
      longitude,
      lastSeenAt: serverReceivedAt,
      streamId: orderedLocation.streamId,
      sequence: orderedLocation.sequence,
    });
    const locationQueued = cached && (await enqueueLocationWork(job));
    const automationQueued =
      !activeTrip || (await enqueueAutomationWork(job));
    if (locationQueued && automationQueued) {
      if (activeTrip) {
        emitJeepneyLocationUpdate({
          tripId: activeTrip._id.toString(),
          routeId: activeTrip.routeId?.toString() || '',
          jeepneyId: jeepneyId.toString(),
          latitude,
          longitude,
          timestamp: serverReceivedAt.toISOString(),
          speedMetersPerSecond: orderedLocation.speedMetersPerSecond,
          headingDegrees: orderedLocation.headingDegrees,
        });
      }
      return ok(res, acknowledgement, 'Location accepted');
    }
  }

  const previousJeepneyState = await Jeepney.findById(jeepneyId).select(
    'lastKnownLocation'
  );
  const previousCoordinates = Array.isArray(
    previousJeepneyState?.lastKnownLocation?.coordinates
  )
    ? previousJeepneyState.lastKnownLocation.coordinates
    : [];
  const previousLongitude =
    previousCoordinates.length >= 2 ? Number(previousCoordinates[0]) : null;
  const previousLatitude =
    previousCoordinates.length >= 2 ? Number(previousCoordinates[1]) : null;

  const locationFilter = orderedLocation
    ? buildPersistentLocationOrderFilter({
        jeepneyId,
        streamId: orderedLocation.streamId,
        sequence: orderedLocation.sequence,
        capturedAt: orderedLocation.capturedAt,
      })
    : { _id: jeepneyId };
  const locationUpdate = {
    lastKnownLocation: {
      type: 'Point',
      coordinates: [longitude, latitude],
    },
    lastSeenAt: serverReceivedAt,
  };
  if (orderedLocation) {
    locationUpdate.latestLocationOrder = persistentLocationOrderUpdate({
      streamId: orderedLocation.streamId,
      sequence: orderedLocation.sequence,
      capturedAt: orderedLocation.capturedAt,
      serverReceivedAt,
    });
  }

  const jeepney = await Jeepney.findOneAndUpdate(
    locationFilter,
    {
      $set: locationUpdate,
    },
    { new: true }
  );
  if (!jeepney) {
    const currentJeepney = await Jeepney.findById(jeepneyId).select(
      'latestLocationOrder'
    );
    if (!currentJeepney) {
      throw new ApiError(404, 'Jeepney location target not found');
    }
    throw stalePersistentLocationError({
      ...(currentJeepney.latestLocationOrder?.toObject?.() ||
        currentJeepney.latestLocationOrder ||
        {}),
      proposedStreamId: orderedLocation?.streamId,
    });
  }
  if (orderedLocation) {
    rememberPersistedDriverLocationOrder({
      jeepneyId,
      streamId: orderedLocation.streamId,
      sequence: orderedLocation.sequence,
      capturedAt: orderedLocation.capturedAt,
      serverReceivedAt,
    });
  }
  await cacheLatestJeepLocation({
    jeepneyId,
    latitude,
    longitude,
    lastSeenAt: serverReceivedAt,
    streamId: orderedLocation?.streamId || null,
    sequence: orderedLocation?.sequence ?? null,
  });

  // Find active trip for this jeepney to broadcast location
  // Broadcast location update via WebSocket
  if (activeTrip) {
    await processDestinationApproachAlerts({
      tripSessionId: activeTrip._id,
      driverUserId: req.user._id,
      latitude,
      longitude,
      previousLatitude,
      previousLongitude,
    });
    await processAutomaticBoardingForTrip({
      tripSessionId: activeTrip._id,
      jeepneyLocation: {
        type: 'Point',
        coordinates: [longitude, latitude],
      },
      now: serverReceivedAt,
    });
    await processAutomaticOffboardingForTrip({
      tripSessionId: activeTrip._id,
      jeepneyLocation: {
        type: 'Point',
        coordinates: [longitude, latitude],
      },
      now: serverReceivedAt,
    });

    emitJeepneyLocationUpdate({
      tripId: activeTrip._id.toString(),
      routeId: activeTrip.routeId?.toString() || '',
      jeepneyId: jeepneyId.toString(),
      latitude,
      longitude,
      timestamp: serverReceivedAt.toISOString(),
      speedMetersPerSecond: orderedLocation?.speedMetersPerSecond,
      headingDegrees: orderedLocation?.headingDegrees,
    });
  }

  return ok(res, acknowledgement, 'Location updated');
};

const locationMethods = ['patch', 'post', 'put'];
for (const method of locationMethods) {
  router[method](
    '/me/location',
    authenticate,
    authorize(DRIVER),
    apiRateLimiters.driverLocation,
    asyncHandler(updateDriverJeepneyLocation)
  );
  router[method](
    '/location',
    authenticate,
    authorize(DRIVER),
    apiRateLimiters.driverLocation,
    asyncHandler(updateDriverJeepneyLocation)
  );
}

module.exports = router;
