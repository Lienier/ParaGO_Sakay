const mongoose = require('mongoose');

const { Schema } = mongoose;

const stopAlertSchema = new Schema(
  {
    passengerId: { type: Schema.Types.ObjectId, ref: 'Passenger', required: true },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession', required: true },
    rideSessionId: { type: Schema.Types.ObjectId, ref: 'RideSession', required: true },
    routeId: { type: Schema.Types.ObjectId, ref: 'Route', required: true },
    stopRef: { type: String, trim: true },
    note: { type: String, trim: true },
    status: {
      type: String,
      enum: ['sent', 'seen', 'acknowledged', 'dismissed'],
      default: 'sent',
    },
    acknowledgedBy: { type: Schema.Types.ObjectId, ref: 'Driver' },
    acknowledgedAt: { type: Date },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number] },
    },
  },
  { timestamps: true }
);

stopAlertSchema.index({ tripSessionId: 1, status: 1 });
stopAlertSchema.index({ passengerId: 1, status: 1 });
stopAlertSchema.index({ createdAt: -1 });

module.exports = mongoose.model('StopAlert', stopAlertSchema);
