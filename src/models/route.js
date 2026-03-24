const mongoose = require('mongoose');

const { Schema } = mongoose;

const stopSchema = new Schema(
  {
    name: { type: String, required: true, trim: true },
    code: { type: String, trim: true },
    order: { type: Number, required: true },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true },
    },
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
        location: {
          type: { type: String, enum: ['Point'], default: 'Point' },
          coordinates: { type: [Number], required: true },
        },
      },
    ],
    stops: [stopSchema],
  },
  { timestamps: true }
);

routeSchema.index({ status: 1 });
routeSchema.index({ path: '2dsphere' });

module.exports = mongoose.model('Route', routeSchema);
