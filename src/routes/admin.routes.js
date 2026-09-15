const terminalQueue = require('../services/terminalQueue.service');
const express = require('express');
const mongoose = require('mongoose');
const { ADMIN } = require('../constants/roles');
const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/response');
const PickupRequest = require('../models/pickupRequest');
const RideSession = require('../models/rideSession');
const StopAlert = require('../models/stopAlert');
const TripSession = require('../models/tripSession');
const ReportMetadata = require('../models/reportMetadata');
const ActivityLog = require('../models/activityLog');
const User = require('../models/user');
const {
  invalidateAuthenticatedUser,
} = require('../services/authUserCache.service');
const Driver = require('../models/driver');
const Jeepney = require('../models/jeepney');
const RouteModel = require('../models/route');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');
const { createUserByAdmin } = require('../services/auth.service');
const { hasOwn, isPlainObject, pickDefined } = require('../utils/object');
const { buildRoutePreview } = require('../services/routePreview.service');
const {
  buildJeepneyCreatePayload,
  buildJeepneyUpdatePayload,
} = require('../utils/transportPayloads');
const {
  compareTerminalQueueTrips,
  nextTerminalQueueNumber,
  normalizeTerminalQueueStatus,
  normalizeTripOperatingMode,
  resolveRouteTerminalStop,
} = require('../services/hybridDispatch.service');
const { deriveDriverPresence } = require('../services/driverPresence.service');
const {
  invalidateDriverActiveContext,
} = require('../services/activeDriverContext.service');
const {
  licensePairUpload,
  singleLicenseUpload,
} = require('../middlewares/driverLicenseUpload');
const {
  deleteLicenseDocument,
  presentLicenseDocuments,
  uploadLicenseDocument,
} = require('../services/driverLicenseDocuments.service');

const router = express.Router();

const parseDriverCreatePayload = (req) => {
  if (!req.body?.payload) return req.body || {};
  try {
    const parsed = JSON.parse(req.body.payload);
    if (!isPlainObject(parsed)) throw new Error('payload is not an object');
    return parsed;
  } catch (_error) {
    throw new ApiError(400, 'Driver payload must be valid JSON');
  }
};

const buildRoutePathSnapshot = (route) => {
  const coordinates = Array.isArray(route?.path?.coordinates)
    ? route.path.coordinates
    : [];

  if (coordinates.length < 2) {
    return undefined;
  }

  return {
    type: 'LineString',
    coordinates: coordinates.map((entry) => [Number(entry[0]), Number(entry[1])]),
  };
};

const normalizeOptionalObjectId = (value, fieldName, allowMissing = false) => {
  if (value === undefined || value === null || String(value).trim() === '') {
    if (allowMissing) return null;
    throw new ApiError(400, `${fieldName} is required`);
  }
  if (value === null) return null;
  ensureObjectId(value, fieldName);
  return String(value);
};

const buildDriverProfile = async (driver) => {
  if (!driver) return null;
  const populatedDriver = await driver.populate([
    { path: 'userId', select: 'email fullName status role' },
    {
      path: 'assignedJeepneyId',
      select: 'plateNumber jeepneyName capacity status lastSeenAt',
    },
    { path: 'assignedRouteId', select: 'name code status' },
  ]);
  const raw =
    typeof populatedDriver.toObject === 'function'
      ? populatedDriver.toObject()
      : populatedDriver;
  return {
    ...raw,
    ...(await deriveDriverPresence(populatedDriver)),
  };
};

const ensureTerminalQueueRouteSupported = (route, operatingMode) => {
  if (
    normalizeTripOperatingMode(operatingMode) === 'terminal_queue' &&
    !resolveRouteTerminalStop(route)
  ) {
    throw new ApiError(409, 'Selected route has no terminal stop configured');
  }
};

const terminalQueueActiveStatuses = ['waiting', 'loading', 'skipped'];

const populateDispatchTrip = (query) =>
  query
    .populate('driverId', 'userId')
    .populate('jeepneyId', 'plateNumber jeepneyName capacity')
    .populate('routeId', 'name code direction');

const buildHybridDispatchBoard = async () => {
  const [terminalTrips, routeTrips] = await Promise.all([
    populateDispatchTrip(
      TripSession.find({
        status: 'active',
        operatingMode: 'terminal_queue',
      })
    ).sort({ terminalQueueNumber: 1, terminalCheckedInAt: 1, createdAt: 1 }),
    populateDispatchTrip(
      TripSession.find({
        status: 'active',
        operatingMode: 'route',
      })
    ).sort({ startedAt: -1, createdAt: -1 }),
  ]);

  terminalTrips.sort(compareTerminalQueueTrips);
  const terminalTripIds = terminalTrips.map((trip) => trip._id);
  const terminalRequests = terminalTripIds.length
    ? await PickupRequest.find({
        pickupType: 'terminal',
        tripSessionId: { $in: terminalTripIds },
        status: { $in: ['pending', 'acknowledged'] },
      }).sort({ createdAt: 1 })
    : [];

  return {
    terminalQueue: await Promise.all(terminalTrips.map(terminalQueue.describe)),
    waitingTerminalPassengers: terminalRequests,
    routeDrivers: routeTrips,
  };
};

const syncTripTerminalQueueToDriver = async (trip) => {
  if (!trip?.driverId) {
    return;
  }
  await Driver.findByIdAndUpdate(trip.driverId, {
    $set: {
      operatingMode: trip.operatingMode,
      terminalQueueStatus: trip.terminalQueueStatus,
      terminalCheckedInAt: trip.terminalCheckedInAt || trip.startedAt || new Date(),
      terminalQueueNumber: trip.terminalQueueNumber,
      terminalStopRef: trip.terminalStopRef,
    },
  });
};

const requireManageableTerminalQueueTrip = async (tripId) => {
  ensureObjectId(tripId, 'trip id');
  const trip = await TripSession.findById(tripId);
  if (!trip) {
    throw new ApiError(404, 'Terminal queue trip not found');
  }
  if (trip.status !== 'active' || trip.operatingMode !== 'terminal_queue') {
    throw new ApiError(409, 'Trip is not active in terminal queue mode');
  }
  const normalizedStatus = normalizeTerminalQueueStatus(trip.terminalQueueStatus, {
    operatingMode: trip.operatingMode,
  });
  if (!terminalQueueActiveStatuses.includes(normalizedStatus)) {
    throw new ApiError(409, 'Trip is not waiting, loading, or skipped in the terminal queue');
  }
  return trip;
};

const findManageableTerminalQueueTrips = async (trip) => {
  const trips = await TripSession.find({
    routeId: trip.routeId,
    status: 'active',
    operatingMode: 'terminal_queue',
    terminalQueueStatus: { $in: terminalQueueActiveStatuses },
  }).sort({ terminalQueueNumber: 1, terminalCheckedInAt: 1, createdAt: 1 });
  return trips.sort(compareTerminalQueueTrips);
};

const nextQueueNumberForTripRoute = async (trip) => {
  const trips = await TripSession.find({
    routeId: trip.routeId,
    status: { $in: ['scheduled', 'active'] },
    operatingMode: 'terminal_queue',
    _id: { $ne: trip._id },
  }).select('terminalQueueNumber');
  return nextTerminalQueueNumber(trips);
};

const syncJeepneyAssignment = async (driver, newJeepneyId) => {

  const previousJeepneyId = driver.assignedJeepneyId;
  if (previousJeepneyId && String(previousJeepneyId) !== String(newJeepneyId || '')) {
    await Jeepney.updateOne(
      { _id: previousJeepneyId },
      { $unset: { currentDriverId: '' } }
    );
  }

  if (!newJeepneyId) {
    driver.assignedJeepneyId = undefined;
    await driver.save();
    await invalidateDriverActiveContext(driver._id);
    return buildDriverProfile(driver);
  }

  const jeepney = await Jeepney.findById(newJeepneyId);
  if (!jeepney) {
    throw new ApiError(404, 'Jeepney not found');
  }
  if (jeepney.status !== 'active') {
    throw new ApiError(409, 'Jeepney is not active');
  }
  if (jeepney.currentDriverId && String(jeepney.currentDriverId) !== String(driver._id)) {
    throw new ApiError(409, 'Jeepney is already assigned to another driver');
  }

  driver.assignedJeepneyId = newJeepneyId;
  await driver.save();
  jeepney.currentDriverId = driver._id;
  await jeepney.save();
  await invalidateDriverActiveContext(driver._id);
  return buildDriverProfile(driver);
};

router.use(authenticate, authorize(ADMIN));

const CodingHoliday = require('../models/codingHoliday');
router.get('/coding-holidays', asyncHandler(async (_req, res) =>
  ok(res, await CodingHoliday.find().sort({ date: 1 }), 'Coding holidays')));
router.put('/coding-holidays/:date', asyncHandler(async (req, res) => {
  const { date } = req.params;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date)) || new Date(date).toISOString().slice(0, 10) !== date)
    throw new ApiError(400, 'Use a valid YYYY-MM-DD holiday date');
  const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
  if (!name || name.length > 120) throw new ApiError(400, 'Holiday name must contain 1–120 characters');
  return ok(res, await CodingHoliday.findOneAndUpdate({ date }, { name, updatedBy: req.user._id }, { upsert: true, new: true }), 'Holiday saved');
}));
router.delete('/coding-holidays/:date', asyncHandler(async (req, res) => {
  await CodingHoliday.deleteOne({ date: req.params.date });
  return ok(res, {}, 'Holiday removed');
}));

router.get(
  '/dashboard',
  asyncHandler(async (_req, res) => {
    const [activeTrips, pendingRequests, ongoingRides, activeAlerts, routeModeTrips, activeTerminalTrips] = await Promise.all([
      TripSession.countDocuments({ status: 'active' }),
      PickupRequest.countDocuments({ status: 'pending' }),
      RideSession.countDocuments({ status: 'onboard' }),
      StopAlert.countDocuments({ status: { $in: ['sent', 'seen'] } }),
      TripSession.countDocuments({
        status: 'active',
        operatingMode: 'route',
      }),
      TripSession.find({
        status: 'active',
        operatingMode: 'terminal_queue',
      }).select('_id'),
    ]);
    const terminalTripIds = activeTerminalTrips.map((trip) => trip._id);
    const terminalQueueTrips = terminalTripIds.length;
    const terminalRequests = terminalTripIds.length
      ? await PickupRequest.countDocuments({
          pickupType: 'terminal',
          tripSessionId: { $in: terminalTripIds },
          status: { $in: ['pending', 'acknowledged'] },
        })
      : 0;
    return ok(
      res,
      {
        activeTrips,
        pendingRequests,
        onboardRides: ongoingRides,
        activeAlerts,
        terminalQueueTrips,
        routeModeTrips,
        terminalRequests,
      },
      'Admin dashboard summary'
    );
  })
);

router.get(
  '/hybrid-dispatch',
  asyncHandler(async (_req, res) => {
    return ok(res, await buildHybridDispatchBoard(), 'Hybrid dispatch board');
  })
);

for (const endpoint of ['reorder', 'skip', 'status']) {
  router.patch(`/terminal-queue/:tripId/${endpoint}`, asyncHandler(async (req, res) => {
    ensureObjectId(req.params.tripId, 'trip id');
    let action = endpoint;
    if (endpoint === 'skip') action = req.body.skipped === false ? 'restore' : 'skip';
    if (endpoint === 'status') {
      if (req.body.terminalQueueStatus !== 'departed') throw new ApiError(409, 'Loading is managed automatically; use skip/restore for queue changes');
      action = 'depart';
    }
    await terminalQueue.change({ tripId: req.params.tripId, actor: req.user, action,
      direction: req.body.direction, requestId: req.body.requestId, reason: req.body.reason });
    return ok(res, await buildHybridDispatchBoard(), 'Terminal queue updated');
  }));
}

router.get(
  '/drivers',
  asyncHandler(async (_req, res) => {
    const drivers = await Driver.find().sort({ createdAt: -1 });
    const profiles = await Promise.all(drivers.map((driver) => buildDriverProfile(driver)));
    return ok(res, profiles, 'Drivers list');
  })
);

router.post(
  '/route-preview',
  asyncHandler(async (req, res) => {
    const route = await buildRoutePreview(req.body || {});

    return ok(
      res,
      {
        path: route.path,
        distanceMeters: Number(route.distanceMeters || 0),
        durationSeconds: Number(route.durationSeconds || 0),
        rawDurationSeconds: Number(route.rawDurationSeconds || route.durationSeconds || 0),
        trafficDelayInSeconds: Number(route.trafficDelayInSeconds || 0),
        source: route.source || 'tomtom',
      },
      route.source === 'google' ? 'Google route preview' : 'TomTom route preview'
    );
  })
);

router.post(
  '/drivers',
  licensePairUpload,
  asyncHandler(async (req, res) => {
    const body = parseDriverCreatePayload(req);
    const frontFile = req.files?.licenseFront?.[0];
    const backFile = req.files?.licenseBack?.[0];
    const requiredText = ['email', 'password', 'fullName', 'licenseNumber', 'phone'];
    const missingText = requiredText.filter((field) => !String(body[field] || '').trim());
    if (missingText.length) {
      throw new ApiError(400, `${missingText.join(', ')} ${missingText.length === 1 ? 'is' : 'are'} required`);
    }
    if (!frontFile || !backFile) {
      throw new ApiError(400, 'Driver license front and back images are required');
    }
    const jeepneyPayload = buildJeepneyCreatePayload(body.jeepney);

    const requestedAccountStatus = String(
      body.accountStatus ?? body.status ?? 'active'
    ).toLowerCase();
    const accountStatus =
      requestedAccountStatus === 'inactive' ? 'suspended' : requestedAccountStatus;
    if (!['active', 'suspended', 'deactivated'].includes(accountStatus)) {
      throw new ApiError(400, 'status must be one of: active, suspended, deactivated');
    }
    const operatingMode = normalizeTripOperatingMode(body.operatingMode);

    const normalizedRouteId =
      body.assignedRouteId && String(body.assignedRouteId).trim() !== ''
        ? normalizeOptionalObjectId(body.assignedRouteId, 'assignedRouteId', true)
        : null;
    if (operatingMode === 'terminal_queue' && !normalizedRouteId) {
      throw new ApiError(
        409,
        'Assign an active route with a terminal stop before enabling terminal queue mode'
      );
    }

    if (normalizedRouteId) {
      const route = await RouteModel.findById(normalizedRouteId);
      if (!route) {
        throw new ApiError(404, 'Route not found');
      }
      if (route.status !== 'active') {
        throw new ApiError(409, 'Route is not active');
      }
      ensureTerminalQueueRouteSupported(route, operatingMode);
    }

    const existingJeepney = await Jeepney.findOne({ plateNumber: jeepneyPayload.plateNumber });
    if (existingJeepney) {
      throw new ApiError(409, 'Jeepney plate number already exists');
    }

    const preparedDriverId = new mongoose.Types.ObjectId();
    const uploadedDocuments = [];
    const session = await mongoose.startSession();
    let user;
    let driver;
    try {
      const front = await uploadLicenseDocument({
        driverId: preparedDriverId,
        side: 'front',
        file: frontFile,
      });
      uploadedDocuments.push(front);
      const back = await uploadLicenseDocument({
        driverId: preparedDriverId,
        side: 'back',
        file: backFile,
      });
      uploadedDocuments.push(back);

      await session.withTransaction(async () => {
        user = await createUserByAdmin({
          email: body.email,
          password: body.password,
          fullName: body.fullName,
          phone: body.phone,
          role: 'DRIVER',
          driverProfileId: preparedDriverId,
          status: accountStatus,
          session,
      });

      driver = await Driver.findOne({ userId: user._id })
        .select('+licenseDocuments')
        .session(session);
      if (!driver) throw new ApiError(500, 'Driver profile could not be created');

      driver.licenseNumber = String(body.licenseNumber).trim();
      driver.employeeNumber = String(body.employeeNumber || '').trim();
      driver.phone = String(body.phone).trim();
      driver.assignedRouteId = normalizedRouteId || undefined;
      driver.operatingMode = operatingMode;
      driver.terminalQueueStatus = normalizeTerminalQueueStatus(undefined, {
        operatingMode,
      });
      driver.licenseDocuments = { front, back };

      const [jeepney] = await Jeepney.create(
        [{ ...jeepneyPayload, currentDriverId: driver._id }],
        { session }
      );
      driver.assignedJeepneyId = jeepney._id;
      await driver.save({ session });
      });
    } catch (error) {
      if (session.inTransaction()) await session.abortTransaction();
      // If commit acknowledgement was lost, never delete documents belonging
      // to a successfully created driver. Preserve uploads if DB state is unknown.
      const persisted = await Driver.exists({ _id: preparedDriverId }).catch(() => undefined);
      if (persisted === null) await Promise.allSettled(uploadedDocuments.map(deleteLicenseDocument));
      if (persisted !== null) throw new ApiError(503, 'Could not confirm creation. Refresh the driver list before trying again');
      if (error.code === 11000) throw new ApiError(409, 'Driver email or jeepney plate number already exists');
      throw error;
    } finally {
      await session.endSession();
    }

    driver = await Driver.findById(driver._id);
    const profile = await buildDriverProfile(driver);
    return ok(
      res,
      {
        userId: user._id.toString(),
        status: user.status,
        accountStatus: user.status,
        role: user.role,
        driver: profile,
      },
      'Driver created',
      201
    );
  })
);

router.get(
  '/drivers/:id/license-documents',
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'driver id');
    const driver = await Driver.findById(req.params.id).select('+licenseDocuments');
    if (!driver) throw new ApiError(404, 'Driver not found');
    return ok(
      res,
      await presentLicenseDocuments(driver.licenseDocuments),
      'Driver license documents'
    );
  })
);

router.put(
  '/drivers/:id/license-documents/:side',
  singleLicenseUpload,
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'driver id');
    const side = String(req.params.side || '').toLowerCase();
    if (!['front', 'back'].includes(side)) {
      throw new ApiError(400, 'Document side must be front or back');
    }
    if (!req.file) throw new ApiError(400, 'Driver license image is required');

    const driver = await Driver.findById(req.params.id).select('+licenseDocuments');
    if (!driver) throw new ApiError(404, 'Driver not found');
    const previous = driver.licenseDocuments?.[side];
    const uploaded = await uploadLicenseDocument({ driverId: driver._id, side, file: req.file });
    try {
      driver.licenseDocuments = {
        ...(driver.licenseDocuments?.toObject?.() || driver.licenseDocuments || {}),
        [side]: uploaded,
      };
      await driver.save();
    } catch (error) {
      await deleteLicenseDocument(uploaded).catch(() => {});
      throw error;
    }
    await deleteLicenseDocument(previous).catch(() => {});
    return ok(
      res,
      await presentLicenseDocuments(driver.licenseDocuments),
      `Driver license ${side} image replaced`
    );
  })
);

router.patch(
  '/drivers/:id',
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'driver id');
    const body = req.body || {};
    const updates = {};
    const updatesToUnset = {};
    let assignedRouteSnapshot;
    let accountStatus;

    if (hasOwn(body, 'licenseNumber')) updates.licenseNumber = String(body.licenseNumber || '').trim();
    if (hasOwn(body, 'employeeNumber')) updates.employeeNumber = String(body.employeeNumber || '').trim();
    if (hasOwn(body, 'phone')) updates.phone = String(body.phone || '').trim();
    if (hasOwn(body, 'accountStatus') || hasOwn(body, 'status')) {
      const requestedAccountStatus = String(
        body.accountStatus ?? body.status ?? ''
      ).toLowerCase();
      accountStatus =
        requestedAccountStatus === 'inactive'
          ? 'suspended'
          : requestedAccountStatus;
      if (!['active', 'suspended', 'deactivated'].includes(accountStatus)) {
        throw new ApiError(400, 'status must be one of: active, suspended, deactivated');
      }
    }
    if (hasOwn(body, 'operatingMode')) {
      const operatingMode = normalizeTripOperatingMode(body.operatingMode);
      updates.operatingMode = operatingMode;
      updates.terminalQueueStatus = normalizeTerminalQueueStatus(undefined, {
        operatingMode,
      });
      if (operatingMode !== 'terminal_queue') {
        updatesToUnset.terminalCheckedInAt = '';
        updatesToUnset.terminalQueueNumber = '';
        updatesToUnset.terminalStopRef = '';
      }
    }
    if (hasOwn(body, 'assignedRouteId')) {
      if (!body.assignedRouteId) {
        updatesToUnset.assignedRouteId = '';
        if (updates.operatingMode === 'terminal_queue') {
          throw new ApiError(
            409,
            'Assign an active route with a terminal stop before enabling terminal queue mode'
          );
        }
      } else {
        const routeId = normalizeOptionalObjectId(body.assignedRouteId, 'assignedRouteId', true);
        const route = await RouteModel.findById(routeId);
        if (!route) {
          throw new ApiError(404, 'Route not found');
        }
        if (route.status !== 'active') {
          throw new ApiError(409, 'Route is not active');
        }
        ensureTerminalQueueRouteSupported(
          route,
          updates.operatingMode || body.operatingMode
        );
        updates.assignedRouteId = routeId;
        assignedRouteSnapshot = buildRoutePathSnapshot(route);
      }
    }
    if (
      updates.operatingMode === 'terminal_queue' &&
      !hasOwn(body, 'assignedRouteId')
    ) {
      const existingProfile = await Driver.findById(req.params.id).select(
        'assignedRouteId'
      );
      if (!existingProfile) {
        throw new ApiError(404, 'Driver not found');
      }
      if (!existingProfile.assignedRouteId) {
        throw new ApiError(
          409,
          'Assign an active route with a terminal stop before enabling terminal queue mode'
        );
      }
      const route = await RouteModel.findById(existingProfile.assignedRouteId);
      if (!route || route.status !== 'active') {
        throw new ApiError(
          409,
          'Assign an active route with a terminal stop before enabling terminal queue mode'
        );
      }
      ensureTerminalQueueRouteSupported(route, updates.operatingMode);
    }

    const updateAction = {};
    if (Object.keys(updates).length) updateAction.$set = updates;
    if (Object.keys(updatesToUnset).length) updateAction.$unset = updatesToUnset;
    if (!Object.keys(updateAction).length) throw new ApiError(400, 'No valid driver fields provided');

    let profile = await Driver.findByIdAndUpdate(req.params.id, updateAction, { new: true });
    if (!profile) throw new ApiError(404, 'Driver not found');

    if (accountStatus) {
      const updatedUser = await User.findByIdAndUpdate(
        profile.userId,
        { $set: { status: accountStatus } },
        { new: true }
      ).select('_id');
      if (!updatedUser) {
        throw new ApiError(404, 'Driver user account not found');
      }
      await invalidateAuthenticatedUser(updatedUser._id);
      if (accountStatus !== 'active') await require('../services/sessionSecurity.service').revokeSessions({ userId: updatedUser._id });
    }

    if (updates.assignedRouteId) {
      await TripSession.updateMany(
        {
          driverId: profile._id,
          status: { $in: ['scheduled', 'active'] },
        },
        {
          $set: {
            routeId: updates.assignedRouteId,
            routePathSnapshot: assignedRouteSnapshot,
          },
        }
      );
    }

    if (hasOwn(body, 'jeepney')) {
      const jeepneyUpdates = buildJeepneyUpdatePayload(body.jeepney);
      if (Object.keys(jeepneyUpdates).length) {
        if (profile.assignedJeepneyId) {
          const existingPlate = jeepneyUpdates.plateNumber
            ? await Jeepney.findOne({
                plateNumber: jeepneyUpdates.plateNumber,
                _id: { $ne: profile.assignedJeepneyId },
              })
            : null;
          if (existingPlate) {
            throw new ApiError(409, 'Jeepney plate number already exists');
          }

          const jeepney = await Jeepney.findByIdAndUpdate(
            profile.assignedJeepneyId,
            { $set: jeepneyUpdates },
            { new: true }
          );
          if (!jeepney) {
            throw new ApiError(404, 'Assigned jeepney not found');
          }
        } else {
          if (!jeepneyUpdates.plateNumber) {
            throw new ApiError(400, 'jeepney.plateNumber is required to create a jeepney');
          }
          if (jeepneyUpdates.capacity == null) {
            throw new ApiError(400, 'jeepney.capacity is required to create a jeepney');
          }
          const existingPlate = await Jeepney.findOne({
            plateNumber: jeepneyUpdates.plateNumber,
          });
          if (existingPlate) {
            throw new ApiError(409, 'Jeepney plate number already exists');
          }

          const createdJeepney = await Jeepney.create({
            ...jeepneyUpdates,
            capacityBand: jeepneyUpdates.capacityBand || 'normal',
            status: jeepneyUpdates.status || 'active',
            currentDriverId: profile._id,
          });
          profile.assignedJeepneyId = createdJeepney._id;
          await profile.save();
        }
      }
    }

    await invalidateDriverActiveContext(profile._id);
    return ok(res, await buildDriverProfile(profile), 'Driver updated');
  })
);

router.patch(
  '/drivers/:id/assign-jeepney',
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'driver id');
    const body = req.body || {};
    const targetDriver = await Driver.findById(req.params.id);
    if (!targetDriver) throw new ApiError(404, 'Driver not found');

    if (!hasOwn(body, 'jeepneyId')) {
      throw new ApiError(400, 'jeepneyId is required. Use null to clear the assignment.');
    }

    const jeepneyId = body.jeepneyId
      ? normalizeOptionalObjectId(body.jeepneyId, 'jeepneyId', true)
      : null;
    if (jeepneyId === null) {
      const assigned = await syncJeepneyAssignment(targetDriver, null);
      return ok(res, assigned, 'Jeepney assignment cleared');
    }

    const assigned = await syncJeepneyAssignment(targetDriver, jeepneyId);
    return ok(res, assigned, 'Driver jeepney assignment updated');
  })
);

router.post(
  '/drivers/:id/assign-jeepney',
  asyncHandler(async (req, res) => {
    ensureObjectId(req.params.id, 'driver id');
    const targetDriver = await Driver.findById(req.params.id);
    if (!targetDriver) throw new ApiError(404, 'Driver not found');

    const jeepneyId = normalizeOptionalObjectId(req.body?.jeepneyId, 'jeepneyId');
    const assigned = await syncJeepneyAssignment(targetDriver, jeepneyId);
    return ok(res, assigned, 'Driver jeepney assignment updated');
  })
);

router.get(
  '/recent-activity',
  asyncHandler(async (req, res) => {
    const limit = Math.min(Math.max(Number(req.query.limit || 40), 1), 200);
    const logs = await ActivityLog.find().sort({ createdAt: -1 }).limit(limit);
    return ok(res, logs, 'Recent activity logs');
  })
);

router.get(
  '/reports',
  asyncHandler(async (req, res) => {
    const reports = await ReportMetadata.find().sort({ createdAt: -1 }).limit(20);
    return ok(res, reports, 'Saved reports');
  })
);

router.post(
  '/activity',
  asyncHandler(async (req, res) => {
    const payload = pickDefined(req.body || {}, ['action', 'entity', 'entityId', 'details', 'client']);
    if (!payload.action || !String(payload.action).trim()) {
      throw new ApiError(400, 'action is required');
    }
    if (!payload.entity || !String(payload.entity).trim()) {
      throw new ApiError(400, 'entity is required');
    }
    if (payload.details !== undefined && !isPlainObject(payload.details)) {
      throw new ApiError(400, 'details must be an object');
    }

    const log = await ActivityLog.create({
      actorId: req.user._id,
      actorRole: req.user.role,
      action: String(payload.action).trim(),
      entity: String(payload.entity).trim(),
      entityId: payload.entityId ? String(payload.entityId).trim() : undefined,
      details: payload.details || {},
      ip: req.ip,
      client: payload.client ? String(payload.client).trim() : undefined,
    });
    return ok(res, log, 'Activity logged', 201);
  })
);

module.exports = router;
