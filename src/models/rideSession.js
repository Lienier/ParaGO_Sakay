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
    flowVersion: { type: Number, enum: [1, 2], default: 1 },
    members: { type: [require('./journeyMember')], default: undefined },
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
    partySize: { type: Number, default: 1, min: 1, validate: Number.isSafeInteger },
    boardedCount: { type: Number, default: 1, min: 1, validate: Number.isSafeInteger },
    remainingCount: { type: Number, default: 1, min: 0, validate: Number.isSafeInteger },
    revision: { type: Number, default: 0, min: 0, validate: Number.isSafeInteger },
    regularTotal: { type: Number, min: 0 },
    boardingMutationId: String,
    unloadMutations: { type: [new Schema({
      memberIds: [String], destinationStopRef: String, destinationLocation: { type: { type: String, enum: ['Point'] }, coordinates: [Number] },
      requestId: String, actorId: String, count: Number, revision: Number,
      actorRole: String, method: String,
      remainingCount: Number, at: Date,
    }, { _id: false })], default: [] },
    status: {
      type: String,
      enum: ['waiting', 'onboard', 'completed'],
      default: 'waiting',
    },
    destinationArrival: { streamId: String, sequence: Number, destinationKey: String, startedAt: Date, lastCapturedAt: Date, observations: Number },
    lastAutomationCheck: { at: Date, reason: String, streamId: String, sequence: Number },
    offboardingMethod: {
      type: String,
      enum: ['manual', 'auto_separation', 'auto_destination', 'trip_ended'],
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

rideSessionSchema.pre('validate', function(next) {
  if (this.flowVersion !== 2) return next();
  if (!this.members?.length || this.members.filter(m => m.organizer).length !== 1 || new Set(this.members.map(m => m.memberId)).size !== this.members.length) return next(new Error('A booking needs one organizer and unique members'));
  this.partySize = this.members.length;
  this.regularTotal = Math.round(this.members.reduce((sum, m) => sum + m.fareSnapshot.amount, 0) * 100) / 100;
  this.boardedCount = this.members.filter(m => m.status === 'onboard' || m.status === 'completed').length;
  this.remainingCount = this.members.filter(m => m.status === 'onboard').length;
  next();
});

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
