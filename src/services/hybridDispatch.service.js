const normalizeTripOperatingMode = (value) => {
  const normalized = String(value || '')
    .trim()
    .toLowerCase();
  return normalized === 'terminal_queue' ? 'terminal_queue' : 'route';
};

const normalizePickupType = (value) => {
  const normalized = String(value || '')
    .trim()
    .toLowerCase();
  return normalized === 'terminal' ? 'terminal' : 'roadside';
};

const isTerminalPickupType = (value) =>
  normalizePickupType(value) === 'terminal';

const normalizeTerminalQueueStatus = (value, { operatingMode } = {}) => {
  const normalized = String(value || '')
    .trim()
    .toLowerCase();

  if (normalizeTripOperatingMode(operatingMode) !== 'terminal_queue') {
    return 'off_queue';
  }

  if (['waiting', 'loading', 'skipped', 'departed'].includes(normalized)) {
    return normalized;
  }
  return 'waiting';
};

const hasValidPoint = (value) => {
  const coordinates = Array.isArray(value?.coordinates) ? value.coordinates : [];
  if (coordinates.length < 2) {
    return false;
  }
  const longitude = Number(coordinates[0]);
  const latitude = Number(coordinates[1]);
  return (
    Number.isFinite(latitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    Number.isFinite(longitude) &&
    longitude >= -180 &&
    longitude <= 180
  );
};

const normalizeTerminalPoint = (value) => ({
  type: 'Point',
  coordinates: [Number(value.coordinates[0]), Number(value.coordinates[1])],
});

const resolveRouteTerminalStop = (route) => {
  const configuredTerminal = route?.terminal;
  if (configuredTerminal && configuredTerminal.enabled === false) {
    return null;
  }
  if (configuredTerminal && hasValidPoint(configuredTerminal.location)) {
    const stopRef = String(
      configuredTerminal.stopRef ||
        configuredTerminal.name ||
        'Route terminal'
    ).trim();
    return {
      stopRef: stopRef || 'Route terminal',
      stopOrder: 0,
      location: normalizeTerminalPoint(configuredTerminal.location),
      radiusMeters: Number(configuredTerminal.radiusMeters || 75),
      source: 'terminal_settings',
    };
  }

  const stops = Array.isArray(route?.stops) ? [...route.stops] : [];
  stops.sort(
    (left, right) => Number(left?.order || 0) - Number(right?.order || 0)
  );

  for (const stop of stops) {
    if (!hasValidPoint(stop?.location)) {
      continue;
    }
    return {
      stopRef: String(stop?.name || stop?.code || 'Route terminal').trim(),
      stopOrder: Number(stop?.order || 0),
      location: normalizeTerminalPoint(stop.location),
      radiusMeters: 75,
      source: 'route_stop',
    };
  }

  return null;
};

const routeHasTerminalStop = (route) => resolveRouteTerminalStop(route) != null;

const nextTerminalQueueNumber = (trips = []) => {
  let maxQueueNumber = 0;
  for (const trip of trips) {
    const queueNumber = Number(trip?.terminalQueueNumber || 0);
    if (Number.isFinite(queueNumber) && queueNumber > maxQueueNumber) {
      maxQueueNumber = queueNumber;
    }
  }
  return maxQueueNumber + 1;
};

const compareTerminalQueueTrips = (left, right) => {
  const leftStatus = normalizeTerminalQueueStatus(left?.terminalQueueStatus, {
    operatingMode: left?.operatingMode,
  });
  const rightStatus = normalizeTerminalQueueStatus(right?.terminalQueueStatus, {
    operatingMode: right?.operatingMode,
  });

  const rankForStatus = (status) => {
    switch (status) {
      case 'loading':
        return 0;
      case 'waiting':
        return 1;
      case 'skipped':
        return 2;
      case 'departed':
        return 3;
      default:
        return 4;
    }
  };

  const statusRankDifference = rankForStatus(leftStatus) - rankForStatus(rightStatus);
  if (statusRankDifference !== 0) {
    return statusRankDifference;
  }

  const leftQueue = Number(left?.terminalQueueNumber || Number.MAX_SAFE_INTEGER);
  const rightQueue = Number(right?.terminalQueueNumber || Number.MAX_SAFE_INTEGER);
  if (leftQueue !== rightQueue) {
    return leftQueue - rightQueue;
  }

  const leftCheckedIn = new Date(
    left?.terminalCheckedInAt || left?.startedAt || left?.createdAt || 0
  ).getTime();
  const rightCheckedIn = new Date(
    right?.terminalCheckedInAt || right?.startedAt || right?.createdAt || 0
  ).getTime();
  return leftCheckedIn - rightCheckedIn;
};

module.exports = {
  normalizePickupType,
  normalizeTerminalQueueStatus,
  normalizeTripOperatingMode,
  isTerminalPickupType,
  routeHasTerminalStop,
  resolveRouteTerminalStop,
  nextTerminalQueueNumber,
  compareTerminalQueueTrips,
};
