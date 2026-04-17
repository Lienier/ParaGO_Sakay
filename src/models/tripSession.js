const mongoose = require('mongoose');

const { Schema } = mongoose;

const tripSessionSchema = new Schema(
  {
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
      enum: ['off_queue', 'waiting', 'loading', 'departed'],
      default: 'off_queue',
    },
    terminalQueueNumber: { type: Number, min: 1 },
    terminalCheckedInAt: { type: Date },
    terminalStopRef: { type: String, trim: true },
    terminalLocation: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: { type: [Number] },
    },
  },
  { timestamps: true }
);

tripSessionSchema.index({ status: 1, startedAt: -1 });
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
