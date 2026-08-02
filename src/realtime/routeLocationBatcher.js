const defaultFlushIntervalMs = 1000;
const defaultMaxBatchSize = 100;
const defaultMaxTrackedRoutes = 200;

const finiteNumber = (value) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

const normalizeIdentifier = (value) => String(value || '').trim();

class RouteLocationBatcher {
  constructor({
    onBatch,
    now = () => new Date(),
    flushIntervalMs = defaultFlushIntervalMs,
    maxBatchSize = defaultMaxBatchSize,
    maxTrackedRoutes = defaultMaxTrackedRoutes,
    autoStart = true,
  } = {}) {
    if (typeof onBatch !== 'function') {
      throw new TypeError('RouteLocationBatcher requires an onBatch callback');
    }
    this.onBatch = onBatch;
    this.now = now;
    this.flushIntervalMs = Math.max(100, Number(flushIntervalMs) || 1000);
    this.maxBatchSize = Math.max(1, Number(maxBatchSize) || 100);
    this.maxTrackedRoutes = Math.max(1, Number(maxTrackedRoutes) || 200);
    this.pendingByRoute = new Map();
    this.latestByRoute = new Map();
    this.sequenceByRoute = new Map();
    this.lastFlushAtByRoute = new Map();
    this.routeActivity = new Map();
    this.timer = null;
    if (autoStart) this.start();
  }

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      this.flushAll();
    }, this.flushIntervalMs);
    this.timer.unref?.();
  }

  stop() {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
  }

  clear() {
    this.pendingByRoute.clear();
    this.latestByRoute.clear();
    this.sequenceByRoute.clear();
    this.lastFlushAtByRoute.clear();
    this.routeActivity.clear();
  }

  enqueue(update) {
    const normalized = this.normalizeUpdate(update);
    if (!normalized) return false;

    this.ensureRouteCapacity(normalized.routeId);
    const pending = this.pendingByRoute.get(normalized.routeId) || new Map();
    const latest = this.latestByRoute.get(normalized.routeId) || new Map();
    this.setBoundedVehicle(pending, normalized.jeepneyId, normalized);
    this.setBoundedVehicle(latest, normalized.jeepneyId, normalized);
    this.pendingByRoute.set(normalized.routeId, pending);
    this.latestByRoute.set(normalized.routeId, latest);
    this.routeActivity.set(normalized.routeId, normalized.receivedAtMs);
    return true;
  }

  normalizeUpdate(update = {}) {
    const routeId = normalizeIdentifier(update.routeId);
    const tripId = normalizeIdentifier(update.tripId);
    const jeepneyId = normalizeIdentifier(update.jeepneyId);
    const latitude = finiteNumber(update.latitude);
    const longitude = finiteNumber(update.longitude);
    if (
      !routeId ||
      !tripId ||
      !jeepneyId ||
      latitude == null ||
      longitude == null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return null;
    }

    const receivedAt = this.now();
    const receivedAtDate =
      receivedAt instanceof Date ? receivedAt : new Date(receivedAt);
    if (Number.isNaN(receivedAtDate.getTime())) return null;
    const speed = finiteNumber(update.speedMetersPerSecond);
    const heading = finiteNumber(update.headingDegrees);

    return {
      routeId,
      tripId,
      jeepneyId,
      latitude,
      longitude,
      speedMetersPerSecond: speed != null && speed >= 0 ? speed : 0,
      headingDegrees:
        heading != null && heading >= 0 && heading <= 360 ? heading : 0,
      lastSeenAt: receivedAtDate.toISOString(),
      receivedAtMs: receivedAtDate.getTime(),
    };
  }

  setBoundedVehicle(target, jeepneyId, update) {
    target.delete(jeepneyId);
    target.set(jeepneyId, update);
    while (target.size > this.maxBatchSize) {
      target.delete(target.keys().next().value);
    }
  }

  ensureRouteCapacity(routeId) {
    if (this.routeActivity.has(routeId)) return;
    while (this.routeActivity.size >= this.maxTrackedRoutes) {
      let oldestRouteId = null;
      let oldestActivity = Number.POSITIVE_INFINITY;
      for (const [candidateRouteId, activity] of this.routeActivity) {
        if (activity < oldestActivity) {
          oldestRouteId = candidateRouteId;
          oldestActivity = activity;
        }
      }
      if (!oldestRouteId) break;
      this.pendingByRoute.delete(oldestRouteId);
      this.latestByRoute.delete(oldestRouteId);
      this.sequenceByRoute.delete(oldestRouteId);
      this.lastFlushAtByRoute.delete(oldestRouteId);
      this.routeActivity.delete(oldestRouteId);
    }
  }

  flushAll() {
    const routeIds = Array.from(this.pendingByRoute.keys());
    for (const routeId of routeIds) {
      this.flushRoute(routeId);
    }
  }

  flushRoute(routeId) {
    const normalizedRouteId = normalizeIdentifier(routeId);
    const pending = this.pendingByRoute.get(normalizedRouteId);
    if (!pending || pending.size === 0) return null;
    const generatedAt = this.now();
    const generatedAtDate =
      generatedAt instanceof Date ? generatedAt : new Date(generatedAt);
    if (Number.isNaN(generatedAtDate.getTime())) return null;
    const lastFlushAt = this.lastFlushAtByRoute.get(normalizedRouteId);
    if (
      lastFlushAt != null &&
      generatedAtDate.getTime() - lastFlushAt < this.flushIntervalMs
    ) {
      return null;
    }

    const sequence = (this.sequenceByRoute.get(normalizedRouteId) || 0) + 1;
    this.sequenceByRoute.set(normalizedRouteId, sequence);
    this.lastFlushAtByRoute.set(normalizedRouteId, generatedAtDate.getTime());
    this.pendingByRoute.delete(normalizedRouteId);
    const payload = this.buildPayload({
      routeId: normalizedRouteId,
      sequence,
      vehicles: Array.from(pending.values()),
      snapshot: false,
      generatedAt: generatedAtDate,
    });
    this.onBatch(payload);
    return payload;
  }

  snapshot(routeId) {
    const normalizedRouteId = normalizeIdentifier(routeId);
    const latest = this.latestByRoute.get(normalizedRouteId);
    if (!latest || latest.size === 0) return null;
    return this.buildPayload({
      routeId: normalizedRouteId,
      sequence: this.sequenceByRoute.get(normalizedRouteId) || 0,
      vehicles: Array.from(latest.values()),
      snapshot: true,
      generatedAt: this.now(),
    });
  }

  buildPayload({ routeId, sequence, vehicles, snapshot, generatedAt }) {
    const generatedAtDate =
      generatedAt instanceof Date ? generatedAt : new Date(generatedAt);
    return {
      routeId,
      sequence,
      generatedAt: generatedAtDate.toISOString(),
      ...(snapshot ? { snapshot: true } : {}),
      vehicles: vehicles.slice(0, this.maxBatchSize).map((vehicle) => ({
        tripId: vehicle.tripId,
        jeepneyId: vehicle.jeepneyId,
        latitude: vehicle.latitude,
        longitude: vehicle.longitude,
        speedMetersPerSecond: vehicle.speedMetersPerSecond,
        headingDegrees: vehicle.headingDegrees,
        lastSeenAt: vehicle.lastSeenAt,
      })),
    };
  }
}

module.exports = {
  RouteLocationBatcher,
  defaultFlushIntervalMs,
  defaultMaxBatchSize,
  defaultMaxTrackedRoutes,
};
