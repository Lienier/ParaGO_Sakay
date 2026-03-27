const mongoose = require('mongoose');

const { Schema } = mongoose;

const geoPointSchema = new Schema(
  {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], required: true },
  },
  { _id: false }
);

const stopSchema = new Schema(
  {
    name: { type: String, required: true, trim: true },
    code: { type: String, trim: true },
    order: { type: Number, required: true },
    fare: { type: Number, min: 0, default: 0 },
    location: geoPointSchema,
  },
  { _id: false }
);

const routeBoundsSchema = new Schema(
  {
    north: { type: Number, required: true },
    south: { type: Number, required: true },
    east: { type: Number, required: true },
    west: { type: Number, required: true },
  },
  { _id: false }
);

const routeSchema = new Schema(
  {
    name: { type: String, required: true, trim: true },
    code: { type: String, required: true, unique: true, trim: true },
    direction: { type: String, enum: ['up', 'down', 'circular'], default: 'circular' },
    status: { type: String, enum: ['active', 'inactive'], default: 'active' },
    description: { type: String, trim: true },
    path: {
      type: {
        type: String,
        enum: ['LineString'],
      },
      coordinates: {
        type: [[Number]],
        default: undefined,
      },
    },
    waypoints: [
      {
        name: { type: String, trim: true },
        location: geoPointSchema,
      },
    ],
    stops: [stopSchema],
    navigation: {
      source: {
        type: String,
        enum: ['openstreetmap', 'cached'],
        default: 'openstreetmap',
      },
      origin: geoPointSchema,
      destination: geoPointSchema,
      bounds: routeBoundsSchema,
      distanceMeters: { type: Number, min: 0 },
      durationSeconds: { type: Number, min: 0 },
    },
  },
  { timestamps: true }
);

routeSchema.index({ status: 1 });
routeSchema.index({ path: '2dsphere' });

module.exports = mongoose.model('Route', routeSchema);
