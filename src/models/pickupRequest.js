const mongoose = require('mongoose');

const { Schema } = mongoose;

const pickupRequestSchema = new Schema(
  {
    passengerId: { type: Schema.Types.ObjectId, ref: 'Passenger', required: true },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession', required: true },
    routeId: { type: Schema.Types.ObjectId, ref: 'Route', required: true },
    stopRef: { type: String, trim: true },
    pickupLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number] },
    },
    status: {
      type: String,
      enum: ['pending', 'acknowledged', 'completed', 'expired', 'cancelled'],
      default: 'pending',
    },
    acknowledgedBy: { type: Schema.Types.ObjectId, ref: 'Driver' },
    acknowledgedAt: { type: Date },
    sourceNote: { type: String, trim: true },
    expiresAt: { type: Date, required: true, index: { expireAfterSeconds: 0 } },
  },
  { timestamps: true }
);

pickupRequestSchema.index({ passengerId: 1, status: 1, createdAt: -1 });
pickupRequestSchema.index({ tripSessionId: 1, status: 1 });
pickupRequestSchema.index({ status: 1, expiresAt: 1 });

module.exports = mongoose.model('PickupRequest', pickupRequestSchema);
