// Latest accepted location per jeep, emitted in bounded chunks every second.
// Unlike route batches this includes assigned jeeps without an active trip.
class FleetLocationBatcher {
  constructor({ onBatch, intervalMs = 1000, maxBatchSize = 100, autoStart = true } = {}) {
    this.onBatch = onBatch;
    this.maxBatchSize = maxBatchSize;
    this.pending = new Map();
    if (autoStart) {
      this.timer = setInterval(() => this.flush(), intervalMs);
      this.timer.unref?.();
    }
  }
  enqueue(update) {
    if (!update?.jeepneyId || !Number.isFinite(update.latitude) || !Number.isFinite(update.longitude) ||
        Math.abs(update.latitude) > 90 || Math.abs(update.longitude) > 180 || !Number.isFinite(Date.parse(update.lastSeenAt))) return false;
    const previous = this.pending.get(update.jeepneyId);
    if (previous && Date.parse(previous.lastSeenAt) > Date.parse(update.lastSeenAt)) return false;
    this.pending.set(update.jeepneyId, update);
    // Bound retained memory while preserving every accepted vehicle in batches.
    if (this.pending.size >= this.maxBatchSize) this.flush();
    return true;
  }
  flush() {
    const vehicles = [...this.pending.values()];
    this.pending.clear();
    for (let i = 0; i < vehicles.length; i += this.maxBatchSize) {
      this.onBatch({ generatedAt: new Date().toISOString(), vehicles: vehicles.slice(i, i + this.maxBatchSize) });
    }
  }
  stop() { clearInterval(this.timer); this.pending.clear(); }
}
module.exports = { FleetLocationBatcher };
