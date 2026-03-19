const mongoose = require('mongoose');

const { Schema } = mongoose;

const jeepneySchema = new Schema(
  {
    plateNumber: { type: String, required: true, unique: true, trim: true, uppercase: true },
    capacity: { type: Number, min: 1 },
    vehicleTag: { type: String, trim: true },
    jeepneyName: { type: String, trim: true },
    manufacturer: { type: String, trim: true },
    capacityBand: { type: String, trim: true, default: 'normal' },
    status: {
      type: String,
      enum: ['active', 'inactive', 'maintenance'],
      default: 'active',
    },
    currentDriverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
    lastKnownLocation: {
      type: { type: String, enum: ['Point'] },
      coordinates: { type: [Number] },
    },
    lastSeenAt: { type: Date },
  },
  { timestamps: true }
);

jeepneySchema.index({ status: 1, currentDriverId: 1 });
jeepneySchema.index({ lastKnownLocation: '2dsphere' });

module.exports = mongoose.model('Jeepney', jeepneySchema);
