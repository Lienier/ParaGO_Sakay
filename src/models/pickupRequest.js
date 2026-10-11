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

const pickupRequestSchema = new Schema(
  {
    flowVersion: { type: Number, enum: [1, 2], default: 1 },
    members: { type: [require('./journeyMember')], default: undefined },
    passengerId: { type: Schema.Types.ObjectId, ref: 'Passenger', required: true },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession', required: true },
    routeId: { type: Schema.Types.ObjectId, ref: 'Route', required: true },
    stopRef: { type: String, trim: true },
    pickupLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number] },
    },
    destinationStopRef: { type: String, trim: true },
    destinationLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number] },
    },
    pickupType: {
      type: String,
      enum: ['roadside', 'terminal'],
      default: 'roadside',
    },
    terminalStopRef: { type: String, trim: true },
    terminalLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number] },
    },
    fareSnapshot: fareSnapshotSchema,
    partySize: { type: Number, default: 1, min: 1, validate: Number.isSafeInteger },
    regularTotal: { type: Number, min: 0 },
    quoteToken: String,
    groupReadyAt: Date,
    status: {
      type: String,
      enum: ['pending', 'acknowledged', 'completed', 'expired', 'cancelled', 'transfer_offered'],
      default: 'pending',
    },
    acknowledgedBy: { type: Schema.Types.ObjectId, ref: 'Driver' },
    acknowledgedAt: { type: Date },
    transferOfferId: String,
    acceptedTransferOfferId: String,
    transferFromTripId: { type: Schema.Types.ObjectId, ref: 'TripSession' },
    autoBoarding: {
      lastReason: String,
      streamId: String,
      tripId: String,
      lastPassengerSampleAt: Date,
      lastDriverSampleAt: Date,
      proximityStartedAt: { type: Date },
      lastCheckedAt: { type: Date },
      lastDistanceMeters: { type: Number, min: 0 },
    },
    sourceNote: { type: String, trim: true },
    // Expiry ends a reservation; it must not delete a ride's booking history.
    expiresAt: { type: Date, required: true, index: true },
  },
  { timestamps: true }
);

pickupRequestSchema.pre('validate', function(next) {
  if (this.flowVersion !== 2) return next();
  if (!this.members?.length || this.members.filter(m => m.organizer).length !== 1 || new Set(this.members.map(m => m.memberId)).size !== this.members.length) return next(new Error('A booking needs one organizer and unique members'));
  this.partySize = this.members.length;
  this.regularTotal = Math.round(this.members.reduce((sum, m) => sum + m.fareSnapshot.amount, 0) * 100) / 100;
  next();
});

pickupRequestSchema.index({ passengerId: 1, status: 1, createdAt: -1 });
pickupRequestSchema.index({ tripSessionId: 1, status: 1 });
pickupRequestSchema.index({ status: 1, expiresAt: 1 });
pickupRequestSchema.index({ destinationLocation: '2dsphere' });
pickupRequestSchema.index({ pickupType: 1, routeId: 1, status: 1 });

module.exports = mongoose.model('PickupRequest', pickupRequestSchema);
