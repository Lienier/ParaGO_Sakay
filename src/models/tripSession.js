const mongoose = require('mongoose');

const { Schema } = mongoose;

const tripSessionSchema = new Schema(
  {
    jeepneyId: { type: Schema.Types.ObjectId, ref: 'Jeepney', required: true },
    driverId: { type: Schema.Types.ObjectId, ref: 'Driver', required: true },
    routeId: { type: Schema.Types.ObjectId, ref: 'Route', required: true },
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
  },
  { timestamps: true }
);

tripSessionSchema.index({ status: 1, startedAt: -1 });
tripSessionSchema.index({ jeepneyId: 1, driverId: 1, status: 1 });

module.exports = mongoose.model('TripSession', tripSessionSchema);
