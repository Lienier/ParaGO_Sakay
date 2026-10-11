const mongoose = require('mongoose');

const { Schema } = mongoose;

const tripSessionSchema = new Schema(
  {
    flowVersion: { type: Number, enum: [1, 2], default: 1 },
    jeepneyId: { type: Schema.Types.ObjectId, ref: 'Jeepney', required: true },
    driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
    routeId: { type: Schema.Types.ObjectId, ref: 'Route', required: true },
    routePathSnapshot: {
      type: {
        type: String,
        enum: ['LineString'],
      },
      coordinates: {
        type: [[Number]],
        default: undefined,
      },
    },
    status: {
      type: String,
      enum: ['scheduled', 'active', 'completed', 'cancelled'],
      default: 'scheduled',
    },
    startedAt: { type: Date },
    endedAt: { type: Date },
    acceptRequests: { type: Boolean, default: true },
    inactivityPausedAt: { type: Date },
    resumedAt: { type: Date },
    lifecycleRevision: { type: Number, default: 0 },
    automaticLifecycle: { type: Boolean, default: false },
    automaticDepartureCheck: { type: Schema.Types.Mixed },
    automaticFinishCheck: { type: Schema.Types.Mixed },
    manualOccupancyCount: { type: Number, default: 0, min: 0 },
    occupancyCount: { type: Number, default: 0, min: 0 },
    active: { type: Boolean, default: false },
    notes: { type: String, trim: true },
    operatingMode: {
      type: String,
      enum: ['route', 'terminal_queue'],
      default: 'route',
    },
    terminalQueueStatus: {
      type: String,
      enum: ['off_queue', 'waiting', 'loading', 'skipped', 'departed'],
      default: 'off_queue',
    },
    terminalQueueNumber: { type: Number, min: 1 },
    terminalCheckedInAt: { type: Date },
    terminalLoadingStartedAt: { type: Date },
    terminalLoadingWarnedAt: { type: Date },
    terminalLoadingExpiredAt: { type: Date },
    terminalStopRef: { type: String, trim: true },
    terminalRadiusMeters: { type: Number, min: 1, default: 75 },
    terminalLocation: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: { type: [Number] },
    },
    terminalArrivalFixCount: { type: Number, min: 0, max: 2, default: 0 },
    terminalArrivalLastAt: { type: Date },
    terminalArrivalLastStreamId: { type: String, trim: true },
    terminalArrivalLastSequence: { type: Number, min: 1 },
    terminalArrivalStatus: {
      type: String,
      enum: [
        'no_ordered_update',
        'stale_location',
        'poor_accuracy',
        'invalid_coordinates',
        'outside_terminal_radius',
        'insufficient_valid_fixes',
        'accepted',
      ],
      default: 'no_ordered_update',
    },
    terminalArrivalReason: { type: String, trim: true },
    terminalArrivalLastDistanceMeters: { type: Number, min: 0 },
    terminalArrivalLastAccuracyMeters: { type: Number, min: 0 },
  },
  { timestamps: true }
);

tripSessionSchema.index({ status: 1, startedAt: -1 });
for (const field of ['driverId', 'jeepneyId']) {
  tripSessionSchema.index(
    { [field]: 1 },
    {
      unique: true,
      name: `unique_terminal_${field}`,
      partialFilterExpression: {
        operatingMode: 'terminal_queue',
        status: { $in: ['scheduled', 'active'] },
        [field]: { $type: 'objectId' },
      },
    }
  );
}
tripSessionSchema.index({ routeId: 1 }, { unique: true, name: 'unique_terminal_loading',
  partialFilterExpression: { operatingMode: 'terminal_queue', status: 'active', terminalQueueStatus: 'loading' } });
tripSessionSchema.index({ jeepneyId: 1, driverId: 1, status: 1 });
tripSessionSchema.index({ routeId: 1, operatingMode: 1, terminalQueueStatus: 1 });
tripSessionSchema.index(
  { routeId: 1, terminalQueueNumber: 1 },
  {
    unique: true,
    partialFilterExpression: {
      operatingMode: 'terminal_queue',
      terminalQueueNumber: { $exists: true },
      status: { $in: ['scheduled', 'active'] },
    },
  }
);

module.exports = mongoose.model('TripSession', tripSessionSchema);
