const ApiError = require('./apiError');
const { ensureLatLng } = require('./validators');
const { hasOwn, isPlainObject } = require('./object');

const normalizeRequiredText = (value, fieldName) => {
  const text = String(value || '').trim();
  if (!text) {
    throw new ApiError(400, `${fieldName} is required`);
  }
  return text;
};

const normalizeOptionalText = (value) => String(value || '').trim();

const normalizePlateNumber = (value, fieldName = 'plateNumber') =>
  normalizeRequiredText(value, fieldName).toUpperCase();

const normalizePositiveInteger = (value, fieldName) => {
  const normalized = Number(value);
  if (!Number.isInteger(normalized) || normalized < 1) {
    throw new ApiError(400, `${fieldName} must be a positive whole number`);
  }
  return normalized;
};

const normalizeNonNegativeNumber = (value, fieldName) => {
  const normalized = Number(value);
  if (!Number.isFinite(normalized) || normalized < 0) {
    throw new ApiError(400, `${fieldName} must be a non-negative number`);
  }
  return normalized;
};

const normalizeFiniteNumber = (value, fieldName) => {
  const normalized = Number(value);
  if (!Number.isFinite(normalized)) {
    throw new ApiError(400, `${fieldName} must be a valid number`);
  }
  return normalized;
};

const normalizeEnum = (value, fieldName, allowedValues) => {
  const normalized = String(value || '').trim().toLowerCase();
  if (!allowedValues.includes(normalized)) {
    throw new ApiError(400, `${fieldName} must be one of: ${allowedValues.join(', ')}`);
  }
  return normalized;
};

const normalizeGeoPoint = (value, fieldName) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `${fieldName} must be an object`);
  }
  const coordinates = Array.isArray(value.coordinates) ? value.coordinates : [];
  if (coordinates.length !== 2) {
    throw new ApiError(400, `${fieldName}.coordinates must contain [lng, lat]`);
  }
  const [lng, lat] = coordinates;
  ensureLatLng(lat, lng, fieldName);
  return {
    type: 'Point',
    coordinates: [Number(lng), Number(lat)],
  };
};

const normalizeGeoLine = (value, fieldName) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `${fieldName} must be an object`);
  }
  const coordinates = Array.isArray(value.coordinates) ? value.coordinates : [];
  if (coordinates.length < 2) {
    throw new ApiError(400, `${fieldName}.coordinates must contain at least two [lng, lat] pairs`);
  }
  return {
    type: 'LineString',
    coordinates: coordinates.map((entry, index) => {
      if (!Array.isArray(entry) || entry.length !== 2) {
        throw new ApiError(
          400,
          `${fieldName}.coordinates[${index}] must contain [lng, lat]`
        );
      }
      const [lng, lat] = entry;
      ensureLatLng(lat, lng, `${fieldName}.coordinates[${index}]`);
      return [Number(lng), Number(lat)];
    }),
  };
};

const buildJeepneyCreatePayload = (value = {}) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, 'jeepney payload is required');
  }

  return {
    plateNumber: normalizePlateNumber(value.plateNumber, 'jeepney.plateNumber'),
    capacity: normalizePositiveInteger(value.capacity, 'jeepney.capacity'),
    vehicleTag: normalizeOptionalText(value.vehicleTag),
    jeepneyName: normalizeOptionalText(value.jeepneyName),
    manufacturer: normalizeOptionalText(value.manufacturer),
    capacityBand: normalizeOptionalText(value.capacityBand) || 'normal',
    status: value.status
      ? normalizeEnum(value.status, 'jeepney.status', ['active', 'inactive', 'maintenance'])
      : 'active',
  };
};

const buildJeepneyUpdatePayload = (value = {}) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, 'jeepney payload must be an object');
  }

  const updates = {};
  if (hasOwn(value, 'plateNumber')) {
    updates.plateNumber = normalizePlateNumber(value.plateNumber, 'jeepney.plateNumber');
  }
  if (hasOwn(value, 'capacity')) {
    updates.capacity = normalizePositiveInteger(value.capacity, 'jeepney.capacity');
  }
  if (hasOwn(value, 'vehicleTag')) {
    updates.vehicleTag = normalizeOptionalText(value.vehicleTag);
  }
  if (hasOwn(value, 'jeepneyName')) {
    updates.jeepneyName = normalizeOptionalText(value.jeepneyName);
  }
  if (hasOwn(value, 'manufacturer')) {
    updates.manufacturer = normalizeOptionalText(value.manufacturer);
  }
  if (hasOwn(value, 'capacityBand')) {
    updates.capacityBand = normalizeOptionalText(value.capacityBand) || 'normal';
  }
  if (hasOwn(value, 'status')) {
    updates.status = normalizeEnum(value.status, 'jeepney.status', [
      'active',
      'inactive',
      'maintenance',
    ]);
  }
  return updates;
};

const buildRouteWaypoint = (value, fieldName) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `${fieldName} must be an object`);
  }

  return {
    name: normalizeOptionalText(value.name),
    location: normalizeGeoPoint(value.location, `${fieldName}.location`),
  };
};

const buildRouteStop = (value, index) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `stops[${index}] must be an object`);
  }

  return {
    name: normalizeRequiredText(value.name, `stops[${index}].name`),
    code: normalizeOptionalText(value.code),
    order: Number.isInteger(Number(value.order))
      ? Number(value.order)
      : (() => {
          throw new ApiError(400, `stops[${index}].order must be an integer`);
        })(),
    fare: hasOwn(value, 'fare')
      ? normalizeNonNegativeNumber(value.fare, `stops[${index}].fare`)
      : 0,
    location: normalizeGeoPoint(value.location, `stops[${index}].location`),
  };
};

const buildRouteBounds = (value, fieldName) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `${fieldName} must be an object`);
  }

  const bounds = {
    north: normalizeFiniteNumber(value.north, `${fieldName}.north`),
    south: normalizeFiniteNumber(value.south, `${fieldName}.south`),
    east: normalizeFiniteNumber(value.east, `${fieldName}.east`),
    west: normalizeFiniteNumber(value.west, `${fieldName}.west`),
  };

  if (bounds.north < bounds.south) {
    throw new ApiError(400, `${fieldName}.north must be greater than or equal to south`);
  }
  if (bounds.east < bounds.west) {
    throw new ApiError(400, `${fieldName}.east must be greater than or equal to west`);
  }

  return bounds;
};

const buildRouteNavigationPayload = (value, fieldName = 'navigation') => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `${fieldName} must be an object`);
  }

  const payload = {
    source: value.source
      ? normalizeEnum(value.source, `${fieldName}.source`, ['openstreetmap', 'cached'])
      : 'openstreetmap',
    origin: normalizeGeoPoint(value.origin, `${fieldName}.origin`),
    destination: normalizeGeoPoint(value.destination, `${fieldName}.destination`),
  };

  if (hasOwn(value, 'bounds')) {
    payload.bounds = buildRouteBounds(value.bounds, `${fieldName}.bounds`);
  }
  if (hasOwn(value, 'distanceMeters')) {
    payload.distanceMeters = normalizeNonNegativeNumber(
      value.distanceMeters,
      `${fieldName}.distanceMeters`
    );
  }
  if (hasOwn(value, 'durationSeconds')) {
    payload.durationSeconds = normalizeNonNegativeNumber(
      value.durationSeconds,
      `${fieldName}.durationSeconds`
    );
  }

  return payload;
};

const buildRouteFareConfig = (value, fieldName = 'fareConfig') => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, `${fieldName} must be an object`);
  }

  return {
    baseAmount: normalizeNonNegativeNumber(
      value.baseAmount,
      `${fieldName}.baseAmount`
    ),
    baseDistanceKm: normalizeNonNegativeNumber(
      value.baseDistanceKm,
      `${fieldName}.baseDistanceKm`
    ),
    additionalAmountPerKm: normalizeNonNegativeNumber(
      value.additionalAmountPerKm,
      `${fieldName}.additionalAmountPerKm`
    ),
  };
};

const buildRouteCreatePayload = (value = {}) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, 'Route payload is required');
  }

  const payload = {
    name: normalizeRequiredText(value.name, 'name'),
    code: normalizeRequiredText(value.code, 'code'),
    direction: value.direction
      ? normalizeEnum(value.direction, 'direction', ['up', 'down', 'circular'])
      : 'circular',
    status: value.status ? normalizeEnum(value.status, 'status', ['active', 'inactive']) : 'active',
    description: normalizeOptionalText(value.description),
    path: undefined,
    waypoints: [],
    stops: [],
    navigation: undefined,
    fareConfig: hasOwn(value, 'fareConfig')
      ? buildRouteFareConfig(value.fareConfig)
      : undefined,
  };

  if (hasOwn(value, 'path')) {
    payload.path = normalizeGeoLine(value.path, 'path');
  }

  if (hasOwn(value, 'waypoints')) {
    if (!Array.isArray(value.waypoints)) {
      throw new ApiError(400, 'waypoints must be an array');
    }
    payload.waypoints = value.waypoints.map((waypoint, index) =>
      buildRouteWaypoint(waypoint, `waypoints[${index}]`)
    );
  }

  if (hasOwn(value, 'stops')) {
    if (!Array.isArray(value.stops)) {
      throw new ApiError(400, 'stops must be an array');
    }
    payload.stops = value.stops.map((stop, index) => buildRouteStop(stop, index));
  }

  if (hasOwn(value, 'navigation')) {
    payload.navigation = buildRouteNavigationPayload(value.navigation);
  }

  return payload;
};

const buildRouteUpdatePayload = (value = {}) => {
  if (!isPlainObject(value)) {
    throw new ApiError(400, 'Route payload must be an object');
  }

  const updates = {};
  if (hasOwn(value, 'name')) {
    updates.name = normalizeRequiredText(value.name, 'name');
  }
  if (hasOwn(value, 'code')) {
    updates.code = normalizeRequiredText(value.code, 'code');
  }
  if (hasOwn(value, 'direction')) {
    updates.direction = normalizeEnum(value.direction, 'direction', ['up', 'down', 'circular']);
  }
  if (hasOwn(value, 'status')) {
    updates.status = normalizeEnum(value.status, 'status', ['active', 'inactive']);
  }
  if (hasOwn(value, 'description')) {
    updates.description = normalizeOptionalText(value.description);
  }
  if (hasOwn(value, 'path')) {
    updates.path = value.path == null ? undefined : normalizeGeoLine(value.path, 'path');
  }
  if (hasOwn(value, 'waypoints')) {
    if (!Array.isArray(value.waypoints)) {
      throw new ApiError(400, 'waypoints must be an array');
    }
    updates.waypoints = value.waypoints.map((waypoint, index) =>
      buildRouteWaypoint(waypoint, `waypoints[${index}]`)
    );
  }
  if (hasOwn(value, 'stops')) {
    if (!Array.isArray(value.stops)) {
      throw new ApiError(400, 'stops must be an array');
    }
    updates.stops = value.stops.map((stop, index) => buildRouteStop(stop, index));
  }
  if (hasOwn(value, 'navigation') && value.navigation != null) {
    updates.navigation = buildRouteNavigationPayload(value.navigation);
  }
  if (hasOwn(value, 'fareConfig') && value.fareConfig != null) {
    updates.fareConfig = buildRouteFareConfig(value.fareConfig);
  }

  return updates;
};

module.exports = {
  buildJeepneyCreatePayload,
  buildJeepneyUpdatePayload,
  buildRouteCreatePayload,
  buildRouteUpdatePayload,
};
