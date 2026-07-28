const axios = require('axios');

const TripSession = require('../models/tripSession');
const Route = require('../models/route');
const ApiError = require('../utils/apiError');
const {
  googleRoutesApiKey,
  pickupRoadProximityMeters,
} = require('../config/env');
const {
  nearestRouteProjection,
  orderedRouteCoordinates,
} = require('../utils/routeGeo');
const { parseDurationSeconds } = require('./routePreview.service');

const GOOGLE_ROUTES_API_URL =
  'https://routes.googleapis.com/directions/v2:computeRoutes';
const ETA_CACHE_TTL_MS = 25 * 1000;
const VEHICLE_LOCATION_MAX_AGE_MS = 60 * 1000;
const MAX_GOOGLE_VIA_POINTS = 10;
const etaCache = new Map();
const pendingEtaRequests = new Map();

const normalizeDestination = (value) => {
  const latitude = Number(value?.latitude);
  const longitude = Number(value?.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new ApiError(
      400,
      'destination must include valid latitude and longitude'
    );
  }
  if (latitude < -90 || latitude > 90) {
    throw new ApiError(400, 'destination.latitude is out of range');
  }
  if (longitude < -180 || longitude > 180) {
    throw new ApiError(400, 'destination.longitude is out of range');
  }
  return { latitude, longitude };
};

const pointCoordinates = (value) => {
  const coordinates = value?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    return null;
  }
  const longitude = Number(coordinates[0]);
  const latitude = Number(coordinates[1]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }
  return [longitude, latitude];
};

const buildRouteGeometry = ({ trip, route }) => {
  const snapshotCoordinates = trip?.routePathSnapshot?.coordinates;
  if (Array.isArray(snapshotCoordinates) && snapshotCoordinates.length >= 2) {
    return {
      path: {
        type: 'LineString',
        coordinates: snapshotCoordinates,
      },
    };
  }
  return route;
};

const sampleEvenly = (points, limit) => {
  if (points.length <= limit) {
    return points;
  }

  const sampled = [];
  for (let index = 0; index < limit; index += 1) {
    const pointIndex = Math.round(
      (index * (points.length - 1)) / Math.max(limit - 1, 1)
    );
    const point = points[pointIndex];
    if (
      point &&
      sampled.every(
        (entry) => entry[0] !== point[0] || entry[1] !== point[1]
      )
    ) {
      sampled.push(point);
    }
  }
  return sampled;
};

const buildRouteSegment = ({ route, origin, destination }) => {
  const originProjection = nearestRouteProjection({
    latitude: origin.latitude,
    longitude: origin.longitude,
    route,
  });
  const destinationProjection = nearestRouteProjection({
    latitude: destination.latitude,
    longitude: destination.longitude,
    route,
  });
  if (!originProjection || !destinationProjection) {
    throw new ApiError(409, 'Trip route geometry is unavailable for ETA');
  }

  const maxDestinationDistance = Number(pickupRoadProximityMeters || 300);
  if (destinationProjection.distanceMeters > maxDestinationDistance) {
    throw new ApiError(
      409,
      'Passenger location is too far from the jeepney route for ETA'
    );
  }
  if (destinationProjection.progress <= originProjection.progress) {
    throw new ApiError(409, 'This jeepney has already passed the pickup point');
  }

  const coordinates = orderedRouteCoordinates(route);
  const startIndex = Math.max(0, Math.ceil(originProjection.progress));
  const endIndex = Math.min(
    coordinates.length - 1,
    Math.floor(destinationProjection.progress)
  );
  const segmentCoordinates = [
    originProjection.coordinates,
    ...(endIndex >= startIndex
      ? coordinates.slice(startIndex, endIndex + 1)
      : []),
    destinationProjection.coordinates,
  ];

  const deduplicated = segmentCoordinates.filter(
    (point, index, values) =>
      index === 0 ||
      point[0] !== values[index - 1][0] ||
      point[1] !== values[index - 1][1]
  );
  const viaCoordinates = sampleEvenly(
    deduplicated.slice(0, -1),
    MAX_GOOGLE_VIA_POINTS
  );

  return {
    destination: {
      latitude: destinationProjection.coordinates[1],
      longitude: destinationProjection.coordinates[0],
    },
    viaPoints: viaCoordinates.map(([longitude, latitude]) => ({
      latitude,
      longitude,
    })),
  };
};

const roundedCoordinate = (value) => Number(value).toFixed(4);

const buildCacheKey = ({ tripId, destination }) =>
  [
    String(tripId),
    roundedCoordinate(destination.latitude),
    roundedCoordinate(destination.longitude),
  ].join(':');

const readCachedEta = (key, now) => {
  const cached = etaCache.get(key);
  if (!cached) return null;
  if (cached.expiresAtMs <= now.getTime()) {
    etaCache.delete(key);
    return null;
  }
  return cached.payload;
};

const requestGoogleEta = async ({ origin, destination, viaPoints }) => {
  if (!googleRoutesApiKey) {
    throw new ApiError(503, 'Passenger traffic ETA is not configured');
  }

  try {
    const response = await axios.post(
      GOOGLE_ROUTES_API_URL,
      {
        origin: {
          location: {
            latLng: origin,
          },
        },
        destination: {
          location: {
            latLng: destination,
          },
        },
        intermediates: viaPoints.map((point) => ({
          location: {
            latLng: point,
          },
          via: true,
        })),
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE_OPTIMAL',
        computeAlternativeRoutes: false,
        languageCode: 'en-US',
        units: 'METRIC',
      },
      {
        timeout: 15000,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': googleRoutesApiKey,
          'X-Goog-FieldMask':
            'routes.duration,routes.staticDuration,routes.distanceMeters',
        },
      }
    );

    const route = Array.isArray(response.data?.routes)
      ? response.data.routes[0]
      : null;
    const durationSeconds = parseDurationSeconds(route?.duration);
    const rawDurationSeconds =
      parseDurationSeconds(route?.staticDuration) ?? durationSeconds;
    const distanceMeters = Number(route?.distanceMeters);
    if (
      !route ||
      durationSeconds == null ||
      rawDurationSeconds == null ||
      !Number.isFinite(distanceMeters)
    ) {
      throw new ApiError(503, 'Google traffic ETA is temporarily unavailable');
    }

    return {
      distanceMeters,
      durationSeconds,
      rawDurationSeconds,
      trafficDelayInSeconds: Math.max(
        durationSeconds - rawDurationSeconds,
        0
      ),
    };
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    throw new ApiError(503, 'Google traffic ETA is temporarily unavailable');
  }
};

const calculatePassengerEta = async ({ tripId, destination }) => {
  const normalizedDestination = normalizeDestination(destination);
  const cacheKey = buildCacheKey({
    tripId,
    destination: normalizedDestination,
  });
  const now = new Date();
  const cached = readCachedEta(cacheKey, now);
  if (cached) {
    return cached;
  }

  const pending = pendingEtaRequests.get(cacheKey);
  if (pending) {
    return pending;
  }

  const request = (async () => {
    const trip = await TripSession.findById(tripId).populate(
      'jeepneyId',
      'plateNumber status lastKnownLocation lastSeenAt'
    );
    if (!trip) {
      throw new ApiError(404, 'Trip not found');
    }
    if (trip.status !== 'active' || trip.active === false) {
      throw new ApiError(409, 'Passenger ETA requires an active trip');
    }

    const jeepney = trip.jeepneyId;
    if (!jeepney || jeepney.status !== 'active') {
      throw new ApiError(409, 'The trip jeepney is not active');
    }
    const jeepneyCoordinates = pointCoordinates(jeepney.lastKnownLocation);
    const lastSeenAt = jeepney.lastSeenAt
      ? new Date(jeepney.lastSeenAt)
      : null;
    if (
      !jeepneyCoordinates ||
      !lastSeenAt ||
      Number.isNaN(lastSeenAt.getTime()) ||
      now.getTime() - lastSeenAt.getTime() > VEHICLE_LOCATION_MAX_AGE_MS
    ) {
      throw new ApiError(409, 'The jeepney location is not fresh enough for ETA');
    }

    const route = await Route.findById(trip.routeId);
    const routeGeometry = buildRouteGeometry({ trip, route });
    const origin = {
      latitude: jeepneyCoordinates[1],
      longitude: jeepneyCoordinates[0],
    };
    const routeSegment = buildRouteSegment({
      route: routeGeometry,
      origin,
      destination: normalizedDestination,
    });
    const googleEta = await requestGoogleEta({
      origin,
      destination: routeSegment.destination,
      viaPoints: routeSegment.viaPoints,
    });
    const calculatedAt = new Date();
    const expiresAt = new Date(calculatedAt.getTime() + ETA_CACHE_TTL_MS);
    const payload = {
      tripId: String(trip._id),
      jeepneyId: String(jeepney._id),
      plateNumber: jeepney.plateNumber,
      ...googleEta,
      source: 'google',
      vehicleLocationLastSeenAt: lastSeenAt.toISOString(),
      calculatedAt: calculatedAt.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };

    etaCache.set(cacheKey, {
      payload,
      expiresAtMs: expiresAt.getTime(),
    });
    return payload;
  })().finally(() => {
    pendingEtaRequests.delete(cacheKey);
  });

  pendingEtaRequests.set(cacheKey, request);
  return request;
};

module.exports = {
  ETA_CACHE_TTL_MS,
  VEHICLE_LOCATION_MAX_AGE_MS,
  buildCacheKey,
  buildRouteSegment,
  calculatePassengerEta,
  normalizeDestination,
  sampleEvenly,
};
