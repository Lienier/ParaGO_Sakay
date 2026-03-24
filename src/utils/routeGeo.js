const { haversineMeters } = require('./geo');

const normalizeCoordinatePair = (value) => {
  if (!value || !Array.isArray(value) || value.length < 2) {
    return null;
  }
  const lng = Number(value[0]);
  const lat = Number(value[1]);
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) {
    return null;
  }
  return [lng, lat];
};

const collectRouteCoordinates = (route) => {
  const coordinates = [];

  for (const pair of route?.path?.coordinates || []) {
    const normalized = normalizeCoordinatePair(pair);
    if (normalized) coordinates.push(normalized);
  }

  for (const stop of route?.stops || []) {
    const pair = normalizeCoordinatePair(stop?.location?.coordinates);
    if (pair) coordinates.push(pair);
  }

  for (const waypoint of route?.waypoints || []) {
    const pair = normalizeCoordinatePair(waypoint?.location?.coordinates);
    if (pair) coordinates.push(pair);
  }

  return coordinates;
};

const isRoutePickupNearRoad = ({ latitude, longitude, route, maxDistanceMeters }) => {
  const coords = collectRouteCoordinates(route);
  if (!coords.length) return false;
  const tolerance = Number(maxDistanceMeters);
  if (!Number.isFinite(tolerance) || tolerance <= 0) return true;

  return coords.some(([lng, lat]) => {
    const distance = haversineMeters(latitude, longitude, lat, lng);
    return distance <= tolerance;
  });
};

const pickDefaultRouteCoordinate = (route) => {
  const coords = collectRouteCoordinates(route);
  if (!coords.length) return null;
  const [lng, lat] = coords[0];
  return {
    type: 'Point',
    coordinates: [lng, lat],
  };
};

module.exports = {
  collectRouteCoordinates,
  isRoutePickupNearRoad,
  pickDefaultRouteCoordinate,
};
