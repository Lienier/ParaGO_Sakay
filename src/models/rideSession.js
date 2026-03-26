const mongoose = require('mongoose');

const { Schema } = mongoose;

const rideSessionSchema = new Schema(
  {
    passengerId: { type: Schema.Types.ObjectId, ref: 'Passenger', required: true },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession', required: true },
    pickupRequestId: { type: Schema.Types.ObjectId, ref: 'PickupRequest', required: true },
    // Enforced at boarding validation time so legacy ride sessions can still be updated safely.
    destinationStopRef: { type: String, trim: true },
    destinationLocation: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: { type: [Number] },
    },
    status: {
      type: String,
      enum: ['waiting', 'onboard', 'completed'],
      default: 'waiting',
    },
    boardedAt: { type: Date },
    endedAt: { type: Date },
    canSendStopAlert: { type: Boolean, default: false },
  },
  { timestamps: true }
);

rideSessionSchema.index({ passengerId: 1, tripSessionId: 1, status: 1 });
rideSessionSchema.index({ tripSessionId: 1, status: 1 });
rideSessionSchema.index({ destinationLocation: '2dsphere' });

module.exports = mongoose.model('RideSession', rideSessionSchema);
