const mongoose = require('mongoose');

const { Schema } = mongoose;

const passengerSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
    phone: { type: String, trim: true },
    photoUrl: { type: String },
    emergencyContact: {
      name: { type: String, trim: true },
      phone: { type: String, trim: true },
    },
    defaultRouteId: { type: Schema.Types.ObjectId, ref: 'Route' },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Passenger', passengerSchema);
