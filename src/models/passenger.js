const mongoose = require('mongoose');

const { Schema } = mongoose;
const geoPointSchema = new Schema(
  {
    type: { type: String, enum: ['Point'], required: true },
    coordinates: { type: [Number], required: true },
  },
  { _id: false }
);

const passengerSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
    phone: { type: String, trim: true },
    photoUrl: { type: String },
    journeyRevision: { type: Number, default: 0 },
    savedPlaces: { type: [new Schema({
      name: { type: String, required: true, maxlength: 60 },
      key: { type: String, required: true },
      lat: { type: Number, required: true, min: -90, max: 90 },
      lng: { type: Number, required: true, min: -180, max: 180 },
    })], default: [] },
    emergencyContact: {
      name: { type: String, trim: true },
      phone: { type: String, trim: true },
    },
    defaultRouteId: { type: Schema.Types.ObjectId, ref: 'Route' },
    // A passenger may not have shared a location yet. Keep the whole point
    // absent until both GeoJSON fields are available.
    lastKnownLocation: { type: geoPointSchema, default: undefined },
    lastSeenAt: { type: Date },
  },
  { timestamps: true }
);

passengerSchema.index({ lastKnownLocation: '2dsphere' });

module.exports = mongoose.model('Passenger', passengerSchema);
