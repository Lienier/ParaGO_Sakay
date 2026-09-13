const mongoose = require('mongoose');

const { Schema } = mongoose;

const fareSnapshotSchema = new Schema(
  {
    boardingStopRef: { type: String, trim: true },
    boardingStopOrder: { type: Number, min: 0 },
    boardingFare: { type: Number, min: 0, default: 0 },
    destinationStopRef: { type: String, trim: true },
    destinationStopOrder: { type: Number, min: 0 },
    destinationFare: { type: Number, min: 0, default: 0 },
    amount: { type: Number, min: 0, default: 0 },
  },
  { _id: false }
);

const rideSessionSchema = new Schema(
  {
    passengerId: { type: Schema.Types.ObjectId, ref: 'Passenger', required: true },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession', required: true },
    pickupRequestId: { type: Schema.Types.ObjectId, ref: 'PickupRequest', required: true },
    pickupType: {
      type: String,
      enum: ['roadside', 'terminal'],
      default: 'roadside',
    },
    boardingMethod: {
      type: String,
      enum: ['manual', 'auto_proximity'],
      default: 'manual',
    },
    boardingStopRef: { type: String, trim: true },
    boardingLocation: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: { type: [Number] },
    },
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
    fareSnapshot: fareSnapshotSchema,
    status: {
      type: String,
      enum: ['waiting', 'onboard', 'completed'],
      default: 'waiting',
    },
    offboardingMethod: {
      type: String,
      enum: ['manual', 'auto_separation', 'trip_ended'],
    },
    autoOffboarding: {
      lastPassengerSampleAt: { type: Date },
      separationStartedAt: { type: Date },
      lastCheckedAt: { type: Date },
      lastDistanceMeters: { type: Number, min: 0 },
      outsideCount: { type: Number, min: 0, default: 0 },
    },
    boardedAt: { type: Date },
    endedAt: { type: Date },
    completedByUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    completedByRole: { type: String, enum: ['passenger', 'driver', 'admin', 'system'] },
    canSendStopAlert: { type: Boolean, default: false },
    destinationApproachAlertedAt: { type: Date },
  },
  { timestamps: true }
);

rideSessionSchema.index({ passengerId: 1, tripSessionId: 1, status: 1 });
rideSessionSchema.index({ tripSessionId: 1, status: 1 });
rideSessionSchema.index(
  { pickupRequestId: 1 },
  {
    name: 'uniq_ride_session_pickup_request',
    unique: true,
    partialFilterExpression: {
      pickupRequestId: { $type: 'objectId' },
    },
  }
);
rideSessionSchema.index({ boardingLocation: '2dsphere' });
rideSessionSchema.index({ destinationLocation: '2dsphere' });

module.exports = mongoose.model('RideSession', rideSessionSchema);
