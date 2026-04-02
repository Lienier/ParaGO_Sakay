const { haversineMeters } = require('./geo');
const {
  fareBaseAmount,
  fareBaseDistanceKm,
  fareAdditionalAmountPerKm,
} = require('../config/env');
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

const roundToTwo = (value) => Math.round(Number(value || 0) * 100) / 100;

const resolveFareConfig = (route) => {
  const routeFareConfig = route?.fareConfig || {};
  return {
    baseAmount: Number.isFinite(Number(routeFareConfig.baseAmount))
      ? Number(routeFareConfig.baseAmount)
      : Number.isFinite(Number(fareBaseAmount))
          ? Number(fareBaseAmount)
          : 17,
    baseDistanceKm: Number.isFinite(Number(routeFareConfig.baseDistanceKm))
      ? Number(routeFareConfig.baseDistanceKm)
      : Number.isFinite(Number(fareBaseDistanceKm))
          ? Number(fareBaseDistanceKm)
          : 4,
    additionalAmountPerKm: Number.isFinite(
      Number(routeFareConfig.additionalAmountPerKm)
    )
      ? Number(routeFareConfig.additionalAmountPerKm)
      : Number.isFinite(Number(fareAdditionalAmountPerKm))
          ? Number(fareAdditionalAmountPerKm)
          : 2,
  };
};

const routeCumulativeDistances = (coordinates) => {
  const cumulative = [0];
  for (let index = 0; index < coordinates.length - 1; index += 1) {
    const start = coordinates[index];
    const end = coordinates[index + 1];
    const segmentMeters = haversineMeters(start[1], start[0], end[1], end[0]);
    cumulative.push(cumulative[cumulative.length - 1] + segmentMeters);
  }
  return cumulative;
};

const routeDistanceAtProgress = ({ progress, coordinates, cumulativeDistances }) => {
  if (!coordinates.length || !Number.isFinite(progress)) {
    return 0;
  }
  if (coordinates.length === 1) {
    return 0;
  }

  const maxProgress = coordinates.length - 1;
  const clampedProgress = Math.max(0, Math.min(maxProgress, progress));
  const segmentIndex = Math.min(
    coordinates.length - 2,
    Math.max(0, Math.floor(clampedProgress))
  );
  const fraction = Math.max(0, Math.min(1, clampedProgress - segmentIndex));
  const segmentStart = coordinates[segmentIndex];
  const segmentEnd = coordinates[segmentIndex + 1];
  const segmentMeters = haversineMeters(
    segmentStart[1],
    segmentStart[0],
    segmentEnd[1],
    segmentEnd[0]
  );
  return cumulativeDistances[segmentIndex] + segmentMeters * fraction;
};

const computeDistanceFare = (distanceMeters, fareConfig = {}) => {
  const normalizedDistance = Number(distanceMeters);
  if (!Number.isFinite(normalizedDistance) || normalizedDistance < 0) {
    return 0;
  }

  const baseAmount = Number.isFinite(Number(fareConfig.baseAmount))
    ? Number(fareConfig.baseAmount)
    : 17;
  const baseDistanceMeters =
    (Number.isFinite(Number(fareConfig.baseDistanceKm))
      ? Number(fareConfig.baseDistanceKm)
      : 4) * 1000;
  const additionalAmount = Number.isFinite(Number(fareConfig.additionalAmountPerKm))
    ? Number(fareConfig.additionalAmountPerKm)
    : 2;
  if (normalizedDistance <= baseDistanceMeters) {
    return roundToTwo(baseAmount);
  }
  const additionalKm = Math.ceil((normalizedDistance - baseDistanceMeters) / 1000);
  return roundToTwo(baseAmount + additionalKm * additionalAmount);
};

const routeStopSnapshots = (route) => {
  return [...(route?.stops || [])]
    .map((stop) => {
      const coordinates = normalizeCoordinatePair(stop?.location?.coordinates);
      if (!coordinates) {
        return null;
      }
      const projection = nearestRouteProjection({
        latitude: coordinates[1],
        longitude: coordinates[0],
        route,
      });
      return {
        name: String(stop?.name || '').trim(),
        order: Number(stop?.order || 0),
        fare: Number.isFinite(Number(stop?.fare)) ? Number(stop.fare) : 0,
        coordinates,
        progress: projection?.progress,
      };
    })
    .filter(Boolean)
    .sort((left, right) => {
      const leftProgress = Number.isFinite(left.progress) ? left.progress : left.order;
      const rightProgress = Number.isFinite(right.progress) ? right.progress : right.order;
      if (leftProgress !== rightProgress) {
        return leftProgress - rightProgress;
      }
      return left.order - right.order;
    });
};

const selectNearestStopSnapshot = ({
  stops,
  pointCoordinates,
  pointProgress,
  minProgress,
}) => {
  if (!stops.length || !pointCoordinates) {
    return null;
  }

  const filteredStops =
    Number.isFinite(minProgress)
      ? stops.filter((stop) => {
          const stopProgress = Number.isFinite(stop.progress)
            ? stop.progress
            : stop.order;
          return stopProgress >= minProgress;
        })
      : stops;
  const candidates = filteredStops.length ? filteredStops : stops;

  let nearest = null;
  let nearestScore = Number.POSITIVE_INFINITY;
  let nearestDistance = Number.POSITIVE_INFINITY;

  for (const stop of candidates) {
    const stopProgress = Number.isFinite(stop.progress) ? stop.progress : stop.order;
    const progressDelta = Number.isFinite(pointProgress)
      ? Math.abs(stopProgress - pointProgress)
      : 0;
    const distanceMeters = haversineMeters(
      pointCoordinates[1],
      pointCoordinates[0],
      stop.coordinates[1],
      stop.coordinates[0]
    );
    const score = Number.isFinite(pointProgress)
      ? progressDelta * 1000 + distanceMeters
      : distanceMeters;
    if (
      !nearest ||
      score < nearestScore ||
      (score === nearestScore && distanceMeters < nearestDistance)
    ) {
      nearest = stop;
      nearestScore = score;
      nearestDistance = distanceMeters;
    }
  }

  return nearest;
};

const resolveRouteFareSnapshot = ({ route, pickupLocation, destinationLocation }) => {
  const stops = routeStopSnapshots(route);
  const routeCoordinates = orderedRouteCoordinates(route);
  const cumulativeDistances = routeCumulativeDistances(routeCoordinates);
  const fareConfig = resolveFareConfig(route);

  const pickupCoordinates = normalizeCoordinatePair(pickupLocation?.coordinates);
  const destinationCoordinates = normalizeCoordinatePair(destinationLocation?.coordinates);
  const pickupProjection = pickupCoordinates
    ? nearestRouteProjection({
        latitude: pickupCoordinates[1],
        longitude: pickupCoordinates[0],
        route,
      })
    : null;
  const destinationProjection = destinationCoordinates
    ? nearestRouteProjection({
        latitude: destinationCoordinates[1],
        longitude: destinationCoordinates[0],
        route,
      })
    : null;

  const boardingDistanceFromOrigin = pickupProjection
    ? routeDistanceAtProgress({
        progress: pickupProjection.progress,
        coordinates: routeCoordinates,
        cumulativeDistances,
      })
    : 0;
  const destinationDistanceFromOrigin = destinationProjection
    ? routeDistanceAtProgress({
        progress: destinationProjection.progress,
        coordinates: routeCoordinates,
        cumulativeDistances,
      })
    : boardingDistanceFromOrigin;
  const segmentDistanceMeters = Math.max(
    0,
    destinationDistanceFromOrigin - boardingDistanceFromOrigin
  );

  if (!stops.length) {
    return {
      boardingStopRef: null,
      boardingStopOrder: null,
      boardingFare: roundToTwo(
        computeDistanceFare(boardingDistanceFromOrigin, fareConfig)
      ),
      destinationStopRef: null,
      destinationStopOrder: null,
      destinationFare: roundToTwo(
        computeDistanceFare(destinationDistanceFromOrigin, fareConfig)
      ),
      amount: roundToTwo(computeDistanceFare(segmentDistanceMeters, fareConfig)),
    };
  }

  const boardingStop = selectNearestStopSnapshot({
    stops,
    pointCoordinates: pickupCoordinates,
    pointProgress: pickupProjection?.progress,
  }) || stops[0];
  const boardingProgress = Number.isFinite(boardingStop.progress)
    ? boardingStop.progress
    : boardingStop.order;
  const destinationStop = selectNearestStopSnapshot({
    stops,
    pointCoordinates: destinationCoordinates,
    pointProgress: destinationProjection?.progress,
    minProgress: boardingProgress,
  }) || boardingStop;
  const amount = roundToTwo(computeDistanceFare(segmentDistanceMeters, fareConfig));

  return {
    boardingStopRef: boardingStop.name || null,
    boardingStopOrder: boardingStop.order || null,
    boardingFare: roundToTwo(
      computeDistanceFare(boardingDistanceFromOrigin, fareConfig)
    ),
    destinationStopRef: destinationStop.name || null,
    destinationStopOrder: destinationStop.order || null,
    destinationFare: roundToTwo(
      computeDistanceFare(destinationDistanceFromOrigin, fareConfig)
    ),
    amount,
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
  resolveRouteFareSnapshot,
};
