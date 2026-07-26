const axios = require('axios');

const ApiError = require('../utils/apiError');
const { googleRoutesApiKey, tomtomApiKey } = require('../config/env');

const GOOGLE_ROUTES_API_URL = 'https://routes.googleapis.com/directions/v2:computeRoutes';

const normalizeLatLngPoint = (value, fieldName) => {
  const latitude = Number(value?.latitude);
  const longitude = Number(value?.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new ApiError(400, `${fieldName} must include valid latitude and longitude`);
  }
  if (latitude < -90 || latitude > 90) {
    throw new ApiError(400, `${fieldName}.latitude is out of range`);
  }
  if (longitude < -180 || longitude > 180) {
    throw new ApiError(400, `${fieldName}.longitude is out of range`);
  }
  return { latitude, longitude };
};

const decodePolyline = (encoded = '') => {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const deltaLat = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    lat += deltaLat;

    result = 0;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const deltaLng = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    lng += deltaLng;

    points.push([lng / 1e5, lat / 1e5]);
  }

  return points;
};

const decodeGeoJsonCoordinates = (coordinates) => {
  if (!Array.isArray(coordinates)) {
    return [];
  }

  const points = [];
  for (const entry of coordinates) {
    if (!Array.isArray(entry) || entry.length < 2) continue;
    const longitude = Number(entry[0]);
    const latitude = Number(entry[1]);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;
    points.push([longitude, latitude]);
  }
  return points;
};

const parseDurationSeconds = (value) => {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  const text = String(value || '').trim();
  if (!text) return null;
  const match = text.match(/^(-?\d+(?:\.\d+)?)s$/);
  if (!match) return null;
  const seconds = Number(match[1]);
  return Number.isFinite(seconds) ? seconds : null;
};

const buildTomTomRoutePreview = async ({ startPoint, endPoint, guidePoints }) => {
  if (!tomtomApiKey) {
    throw new ApiError(503, 'TomTom routing is not configured on the server');
  }

  const routePlanningLocations = [startPoint, ...(guidePoints || []), endPoint]
    .map((point) => `${point.latitude},${point.longitude}`)
    .join(':');

  const response = await axios.get(
    `https://api.tomtom.com/routing/1/calculateRoute/${routePlanningLocations}/json`,
    {
      params: {
        key: tomtomApiKey,
        traffic: 'true',
        travelMode: 'car',
        routeRepresentation: 'polyline',
        computeTravelTimeFor: 'all',
        sectionType: 'traffic',
      },
      timeout: 20000,
      headers: {
        Accept: 'application/json',
      },
    }
  );

  const payload = response.data || {};
  const routes = Array.isArray(payload.routes) ? payload.routes : [];
  const route = routes[0];
  const summary = route && typeof route.summary === 'object' ? route.summary : {};
  const coordinates = decodeGeoJsonCoordinates(route?.legs?.flatMap((leg) => {
    const legPoints = Array.isArray(leg?.points) ? leg.points : [];
    return legPoints
      .map((point) => {
        const latitude = Number(point?.latitude);
        const longitude = Number(point?.longitude);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
          return null;
        }
        return [longitude, latitude];
      })
      .filter(Boolean);
  }));

  if (coordinates.length < 2) {
    throw new ApiError(502, 'TomTom did not return valid route geometry');
  }

  return {
    path: {
      type: 'LineString',
      coordinates,
    },
    distanceMeters: Number(summary.lengthInMeters || 0),
    durationSeconds: Number(summary.travelTimeInSeconds || 0),
    rawDurationSeconds: Number(
      summary.noTrafficTravelTimeInSeconds || summary.travelTimeInSeconds || 0
    ),
    trafficDelayInSeconds: Number(summary.trafficDelayInSeconds || 0),
    source: 'tomtom',
  };
};

const buildGoogleRoutePreview = async ({ startPoint, endPoint, guidePoints }) => {
  if (!googleRoutesApiKey) {
    throw new ApiError(503, 'Google Routes API is not configured on the server');
  }

  const response = await axios.post(
    GOOGLE_ROUTES_API_URL,
    {
      origin: {
        location: {
          latLng: {
            latitude: startPoint.latitude,
            longitude: startPoint.longitude,
          },
        },
      },
      destination: {
        location: {
          latLng: {
            latitude: endPoint.latitude,
            longitude: endPoint.longitude,
          },
        },
      },
      intermediates: (guidePoints || []).map((point) => ({
        location: {
          latLng: {
            latitude: point.latitude,
            longitude: point.longitude,
          },
        },
      })),
      travelMode: 'DRIVE',
      routingPreference: 'TRAFFIC_AWARE_OPTIMAL',
      computeAlternativeRoutes: false,
      languageCode: 'en-US',
      units: 'METRIC',
    },
    {
      timeout: 20000,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': googleRoutesApiKey,
        'X-Goog-FieldMask':
          'routes.duration,routes.staticDuration,routes.distanceMeters,routes.polyline.encodedPolyline',
      },
    }
  );

  const payload = response.data || {};
  const routes = Array.isArray(payload.routes) ? payload.routes : [];
  const route = routes[0];
  if (!route) {
    throw new ApiError(502, 'Google Routes API did not return any routes');
  }

  const encodedPolyline = route?.polyline?.encodedPolyline;
  const geoJsonPolyline = route?.polyline?.geoJsonLinestring?.coordinates;
  const points = encodedPolyline
    ? decodePolyline(encodedPolyline).map(([longitude, latitude]) => [longitude, latitude])
    : decodeGeoJsonCoordinates(geoJsonPolyline);

  if (points.length < 2) {
    throw new ApiError(502, 'Google Routes API did not return valid route geometry');
  }

  const durationSeconds = parseDurationSeconds(route.duration);
  const rawDurationSeconds = parseDurationSeconds(route.staticDuration) ?? durationSeconds;
  const trafficDelayInSeconds =
    durationSeconds != null && rawDurationSeconds != null
      ? Math.max(durationSeconds - rawDurationSeconds, 0)
      : null;

  return {
    path: {
      type: 'LineString',
      coordinates: points,
    },
    distanceMeters: Number(route.distanceMeters || 0),
    durationSeconds: durationSeconds ?? 0,
    rawDurationSeconds: rawDurationSeconds ?? durationSeconds ?? 0,
    trafficDelayInSeconds: trafficDelayInSeconds ?? 0,
    source: 'google',
  };
};

const buildRoutePreview = async ({ startPoint, endPoint, guidePoints = [] }) => {
  const normalizedStartPoint = normalizeLatLngPoint(startPoint, 'startPoint');
  const normalizedEndPoint = normalizeLatLngPoint(endPoint, 'endPoint');
  const normalizedGuidePoints = Array.isArray(guidePoints)
    ? guidePoints.map((point, index) =>
        normalizeLatLngPoint(point, `guidePoints[${index}]`)
      )
    : [];

  if (googleRoutesApiKey) {
    try {
      return await buildGoogleRoutePreview({
        startPoint: normalizedStartPoint,
        endPoint: normalizedEndPoint,
        guidePoints: normalizedGuidePoints,
      });
    } catch (error) {
      if (error instanceof ApiError && error.statusCode >= 400 && error.statusCode < 500) {
        throw error;
      }
      // Fall back to TomTom when Google is unavailable or returns a server-side failure.
    }
  }

  return buildTomTomRoutePreview({
    startPoint: normalizedStartPoint,
    endPoint: normalizedEndPoint,
    guidePoints: normalizedGuidePoints,
  });
};

module.exports = {
  buildRoutePreview,
  decodePolyline,
  parseDurationSeconds,
};
