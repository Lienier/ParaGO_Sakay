const { Schema } = require('mongoose');

module.exports = new Schema({
  memberId: { type: String, required: true },
  organizer: { type: Boolean, required: true },
  label: { type: String, required: true },
  destinationStopRef: { type: String, required: true },
  destinationLocation: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: [Number],
  },
  fareSnapshot: {
    boardingStopRef: String, boardingStopOrder: Number, boardingFare: Number,
    destinationStopRef: String, destinationStopOrder: Number, destinationFare: Number, amount: Number,
  },
  status: { type: String, enum: ['reserved', 'onboard', 'completed', 'cancelled'], default: 'reserved' },
  boardedAt: Date,
  completedAt: Date,
  completionMethod: String,
  approachAlertedAt: Date,
}, { _id: false });
