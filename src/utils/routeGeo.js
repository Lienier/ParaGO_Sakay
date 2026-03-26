const { haversineMeters } = require('./geo');
const METERS_PER_DEGREE_LAT = 111320;

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

const orderedRouteCoordinates = (route) => {
  const pathCoordinates = [];
  for (const pair of route?.path?.coordinates || []) {
    const normalized = normalizeCoordinatePair(pair);
    if (normalized) pathCoordinates.push(normalized);
  }
  if (pathCoordinates.length) {
    return pathCoordinates;
  }

  const stopCoordinates = [...(route?.stops || [])]
    .sort((left, right) => Number(left?.order || 0) - Number(right?.order || 0))
    .map((stop) => normalizeCoordinatePair(stop?.location?.coordinates))
    .filter(Boolean);
  if (stopCoordinates.length) {
    return stopCoordinates;
  }

  return (route?.waypoints || [])
    .map((waypoint) => normalizeCoordinatePair(waypoint?.location?.coordinates))
    .filter(Boolean);
};

const toLocalMeters = ({ lng, lat, originLat, originLng }) => {
  const metersPerDegreeLng =
    METERS_PER_DEGREE_LAT * Math.cos((originLat * Math.PI) / 180);
  return {
    x: (lng - originLng) * metersPerDegreeLng,
    y: (lat - originLat) * METERS_PER_DEGREE_LAT,
  };
};

const fromLocalMeters = ({ x, y, originLat, originLng }) => {
  const metersPerDegreeLng =
    METERS_PER_DEGREE_LAT * Math.cos((originLat * Math.PI) / 180);
  return [
    originLng + x / (metersPerDegreeLng || 1),
    originLat + y / METERS_PER_DEGREE_LAT,
  ];
};

const projectOnSegment = ({ point, start, end }) => {
  const originLat = (point[1] + start[1] + end[1]) / 3;
  const originLng = (point[0] + start[0] + end[0]) / 3;
  const localPoint = toLocalMeters({
    lng: point[0],
    lat: point[1],
    originLat,
    originLng,
  });
  const localStart = toLocalMeters({
    lng: start[0],
    lat: start[1],
    originLat,
    originLng,
  });
  const localEnd = toLocalMeters({
    lng: end[0],
    lat: end[1],
    originLat,
    originLng,
  });
  const dx = localEnd.x - localStart.x;
  const dy = localEnd.y - localStart.y;
  const segmentLengthSquared = dx * dx + dy * dy;
  if (segmentLengthSquared <= 0) {
    return {
      coordinates: start,
      distanceMeters: haversineMeters(point[1], point[0], start[1], start[0]),
      fraction: 0,
    };
  }

  const rawFraction =
    ((localPoint.x - localStart.x) * dx + (localPoint.y - localStart.y) * dy) /
    segmentLengthSquared;
  const fraction = Math.max(0, Math.min(1, rawFraction));
  const projected = {
    x: localStart.x + dx * fraction,
    y: localStart.y + dy * fraction,
  };
  const projectedCoordinates = fromLocalMeters({
    ...projected,
    originLat,
    originLng,
  });
  return {
    coordinates: projectedCoordinates,
    distanceMeters: haversineMeters(
      point[1],
      point[0],
      projectedCoordinates[1],
      projectedCoordinates[0]
    ),
    fraction,
  };
};

const nearestRouteProjection = ({ latitude, longitude, route }) => {
  const coords = orderedRouteCoordinates(route);
  if (!coords.length) return null;
  if (coords.length === 1) {
    return {
      coordinates: coords[0],
      distanceMeters: haversineMeters(latitude, longitude, coords[0][1], coords[0][0]),
      progress: 0,
    };
  }

  let nearestProjection = null;
  for (let index = 0; index < coords.length - 1; index += 1) {
    const candidate = projectOnSegment({
      point: [longitude, latitude],
      start: coords[index],
      end: coords[index + 1],
    });
    if (
      !nearestProjection ||
      candidate.distanceMeters < nearestProjection.distanceMeters
    ) {
      nearestProjection = {
        coordinates: candidate.coordinates,
        distanceMeters: candidate.distanceMeters,
        progress: index + candidate.fraction,
      };
    }
  }
  return nearestProjection;
};

const nearestOrderedRouteCoordinateIndex = ({ latitude, longitude, route }) => {
  const projection = nearestRouteProjection({ latitude, longitude, route });
  if (!projection) return null;
  return Math.floor(projection.progress);
};

const isPointAfterOnRoute = ({
  route,
  startLatitude,
  startLongitude,
  endLatitude,
  endLongitude,
}) => {
  const startProjection = nearestRouteProjection({
    latitude: startLatitude,
    longitude: startLongitude,
    route,
  });
  const endProjection = nearestRouteProjection({
    latitude: endLatitude,
    longitude: endLongitude,
    route,
  });
  if (!startProjection || !endProjection) {
    return true;
  }
  return endProjection.progress > startProjection.progress;
};

const isRoutePickupNearRoad = ({ latitude, longitude, route, maxDistanceMeters }) => {
  const projection = nearestRouteProjection({ latitude, longitude, route });
  if (!projection) return false;
  const tolerance = Number(maxDistanceMeters);
  if (!Number.isFinite(tolerance) || tolerance <= 0) return true;
  return projection.distanceMeters <= tolerance;
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
  orderedRouteCoordinates,
  nearestRouteProjection,
  nearestOrderedRouteCoordinateIndex,
  isPointAfterOnRoute,
  isRoutePickupNearRoad,
  pickDefaultRouteCoordinate,
};
