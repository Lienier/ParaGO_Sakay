const mongoose = require('mongoose');

const { Schema } = mongoose;

const rideSessionSchema = new Schema(
  {
    passengerId: { type: Schema.Types.ObjectId, ref: 'Passenger', required: true },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession', required: true },
    pickupRequestId: { type: Schema.Types.ObjectId, ref: 'PickupRequest', required: true },
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

module.exports = mongoose.model('RideSession', rideSessionSchema);
