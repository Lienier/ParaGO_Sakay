const express = require('express');
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
const Driver = require('../models/driver');
const Jeepney = require('../models/jeepney');
const RouteModel = require('../models/route');
const ApiError = require('../utils/apiError');
const { ensureObjectId } = require('../utils/validators');
const { createUserByAdmin } = require('../services/auth.service');

const router = express.Router();

const normalizeOptionalObjectId = (value, fieldName, allowMissing = false) => {
  if (value === undefined || value === null || String(value).trim() === '') {
    if (allowMissing) return null;
    throw new ApiError(400, `${fieldName} is required`);
  }
  if (value === null) return null;
  ensureObjectId(value, fieldName);
  return String(value);
};

const normalizeOptionalText = (value) => {
  const text = String(value || '').trim();
  return text || undefined;
};

const normalizePlateNumber = (value) => {
  const text = String(value || '').trim().toUpperCase();
  return text || undefined;
};

const buildJeepneyCreatePayload = (value) => {
  const payload = value || {};
  const plateNumber = normalizePlateNumber(payload.plateNumber);
  if (!plateNumber) {
    throw new ApiError(400, 'jeepney.plateNumber is required');
  }
  const capacity = Number(payload.capacity);
  if (!Number.isInteger(capacity) || capacity < 1) {
    throw new ApiError(400, 'jeepney.capacity must be a positive whole number');
  }

  const status = payload.status ? String(payload.status).toLowerCase() : 'active';
  if (!['active', 'inactive', 'maintenance'].includes(status)) {
    throw new ApiError(400, 'jeepney.status must be one of: active, inactive, maintenance');
  }

  return {
    plateNumber,
    capacity,
    capacityBand: normalizeOptionalText(payload.capacityBand) || 'normal',
    status,
  };
};

const buildJeepneyUpdatePayload = (value) => {
  const payload = value || {};
  const updates = {};

  if (payload.plateNumber !== undefined) {
    const plateNumber = normalizePlateNumber(payload.plateNumber);
    if (!plateNumber) {
      throw new ApiError(400, 'jeepney.plateNumber cannot be empty');
    }
    updates.plateNumber = plateNumber;
  }
  if (payload.capacity !== undefined) {
    const capacity = Number(payload.capacity);
    if (!Number.isInteger(capacity) || capacity < 1) {
      throw new ApiError(400, 'jeepney.capacity must be a positive whole number');
    }
    updates.capacity = capacity;
  }
  if (payload.capacityBand !== undefined) {
    updates.capacityBand = normalizeOptionalText(payload.capacityBand) || 'normal';
  }
  if (payload.status !== undefined) {
    const status = String(payload.status || '').toLowerCase();
    if (!['active', 'inactive', 'maintenance'].includes(status)) {
      throw new ApiError(400, 'jeepney.status must be one of: active, inactive, maintenance');
    }
    updates.status = status;
  }

  return updates;
};

const buildDriverProfile = async (driver) => {
  if (!driver) return null;
  return driver.populate([
    { path: 'userId', select: 'email fullName status role' },
    { path: 'assignedJeepneyId', select: 'plateNumber capacity status' },
    { path: 'assignedRouteId', select: 'name code status' },
  ]);
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
  return buildDriverProfile(driver);
};

router.use(authenticate, authorize(ADMIN));

router.get(
  '/dashboard',
  asyncHandler(async (_req, res) => {
    const [activeTrips, pendingRequests, ongoingRides, activeAlerts] = await Promise.all([
      TripSession.countDocuments({ status: 'active' }),
      PickupRequest.countDocuments({ status: 'pending' }),
      RideSession.countDocuments({ status: 'onboard' }),
      StopAlert.countDocuments({ status: { $in: ['sent', 'seen'] } }),
    ]);
    return ok(
      res,
      {
        activeTrips,
        pendingRequests,
        onboardRides: ongoingRides,
        activeAlerts,
      },
      'Admin dashboard summary'
    );
  })
);

router.get(
  '/drivers',
  asyncHandler(async (_req, res) => {
    const drivers = await Driver.find()
      .populate('userId', 'email fullName status role')
      .populate('assignedJeepneyId', 'plateNumber jeepneyName status')
      .populate('assignedRouteId', 'name code status')
      .sort({ createdAt: -1 });
    return ok(res, drivers, 'Drivers list');
  })
);

router.post(
  '/drivers',
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    if (!body.email || !body.password || !body.fullName) {
      throw new ApiError(400, 'email, password, and fullName are required');
    }
    const jeepneyPayload = buildJeepneyCreatePayload(body.jeepney);

    const status = String(body.status || 'active').toLowerCase();
    if (!['active', 'inactive'].includes(status)) {
      throw new ApiError(400, 'status must be one of: active, inactive');
    }

    const normalizedRouteId =
      body.assignedRouteId && String(body.assignedRouteId).trim() !== ''
        ? normalizeOptionalObjectId(body.assignedRouteId, 'assignedRouteId', true)
        : null;

    if (normalizedRouteId) {
      const route = await RouteModel.findById(normalizedRouteId);
      if (!route) {
        throw new ApiError(404, 'Route not found');
      }
      if (route.status !== 'active') {
        throw new ApiError(409, 'Route is not active');
      }
    }

    const existingJeepney = await Jeepney.findOne({ plateNumber: jeepneyPayload.plateNumber });
    if (existingJeepney) {
      throw new ApiError(409, 'Jeepney plate number already exists');
    }

    const user = await createUserByAdmin({
      email: body.email,
      password: body.password,
      fullName: body.fullName,
      role: 'DRIVER',
      status,
    });

    const update = {};
    if (body.licenseNumber !== undefined) {
      update.licenseNumber = String(body.licenseNumber || '').trim();
    }
    if (body.employeeNumber !== undefined) {
      update.employeeNumber = String(body.employeeNumber || '').trim();
    }
    if (body.phone !== undefined) {
      update.phone = String(body.phone || '').trim();
    }
    update.status = status;
    if (typeof body.isVerified === 'boolean') update.isVerified = body.isVerified;
    if (normalizedRouteId) {
      update.assignedRouteId = normalizedRouteId;
    }

    const driver = await Driver.findOneAndUpdate(
      { userId: user._id },
      { $set: update },
      { new: true }
    );
    if (!driver) {
      throw new ApiError(500, 'Driver profile could not be created');
    }

    const jeepney = await Jeepney.create({
      ...jeepneyPayload,
      currentDriverId: driver._id,
    });
    driver.assignedJeepneyId = jeepney._id;
    await driver.save();

    const profile = await buildDriverProfile(driver);
    return ok(
      res,
      { userId: user._id.toString(), status: user.status, role: user.role, driver: profile },
      'Driver created',
      201
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

    if (body.licenseNumber !== undefined) updates.licenseNumber = body.licenseNumber || '';
    if (body.employeeNumber !== undefined) updates.employeeNumber = body.employeeNumber || '';
    if (body.phone !== undefined) updates.phone = body.phone || '';
    if (typeof body.isVerified === 'boolean') updates.isVerified = body.isVerified;
    if (body.status !== undefined) {
      if (!['active', 'inactive'].includes(body.status)) {
        throw new ApiError(400, 'status must be one of: active, inactive');
      }
      updates.status = body.status;
    }
    if (body.assignedRouteId !== undefined) {
      if (!body.assignedRouteId) {
        updatesToUnset.assignedRouteId = '';
      } else {
        const routeId = normalizeOptionalObjectId(body.assignedRouteId, 'assignedRouteId', true);
        const route = await RouteModel.findById(routeId);
        if (!route) {
          throw new ApiError(404, 'Route not found');
        }
        if (route.status !== 'active') {
          throw new ApiError(409, 'Route is not active');
        }
        updates.assignedRouteId = routeId;
      }
    }

    const updateAction = {};
    if (Object.keys(updates).length) updateAction.$set = updates;
    if (Object.keys(updatesToUnset).length) updateAction.$unset = updatesToUnset;
    if (!Object.keys(updateAction).length) throw new ApiError(400, 'No valid driver fields provided');

    let profile = await Driver.findByIdAndUpdate(req.params.id, updateAction, { new: true });
    if (!profile) throw new ApiError(404, 'Driver not found');

    if (body.jeepney !== undefined) {
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
          const existingPlate = await Jeepney.findOne({
            plateNumber: jeepneyUpdates.plateNumber,
          });
          if (existingPlate) {
            throw new ApiError(409, 'Jeepney plate number already exists');
          }

          const createdJeepney = await Jeepney.create({
            plateNumber: jeepneyUpdates.plateNumber,
            vehicleTag: jeepneyUpdates.vehicleTag,
            jeepneyName: jeepneyUpdates.jeepneyName,
            manufacturer: jeepneyUpdates.manufacturer,
            capacityBand: jeepneyUpdates.capacityBand || 'normal',
            status: jeepneyUpdates.status || 'active',
            currentDriverId: profile._id,
          });
          profile.assignedJeepneyId = createdJeepney._id;
          await profile.save();
        }
      }
    }

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

    const jeepneyId = body.jeepneyId ? normalizeOptionalObjectId(body.jeepneyId, 'jeepneyId', true) : null;
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
    const log = await ActivityLog.create(req.body || {});
    return ok(res, log, 'Activity logged', 201);
  })
);

module.exports = router;
