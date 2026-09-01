const mongoose = require('mongoose');

const { Schema } = mongoose;

const licenseDocumentSchema = new Schema(
  {
    objectKey: { type: String, required: true, trim: true },
    mimeType: { type: String, required: true, trim: true },
    sizeBytes: { type: Number, required: true, min: 1 },
    uploadedAt: { type: Date, required: true },
  },
  { _id: false }
);

const driverSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
    licenseNumber: { type: String, trim: true },
    employeeNumber: { type: String, trim: true },
    phone: { type: String, trim: true },
    licenseDocuments: {
      type: {
        front: licenseDocumentSchema,
        back: licenseDocumentSchema,
      },
      select: false,
    },
    assignedJeepneyId: { type: Schema.Types.ObjectId, ref: 'Jeepney' },
    assignedRouteId: { type: Schema.Types.ObjectId, ref: 'Route' },
    status: {
      type: String,
      enum: ['active', 'inactive'],
      default: 'inactive',
    },
    operatingMode: {
      type: String,
      enum: ['route', 'terminal_queue'],
      default: 'route',
    },
    terminalQueueStatus: {
      type: String,
      enum: ['off_queue', 'waiting', 'loading', 'skipped', 'departed'],
      default: 'off_queue',
    },
    terminalCheckedInAt: { type: Date },
    terminalQueueNumber: { type: Number, min: 1 },
    terminalStopRef: { type: String, trim: true },
  },
  { timestamps: true }
);

driverSchema.index({ assignedRouteId: 1, status: 1 });
driverSchema.index({ assignedRouteId: 1, operatingMode: 1, terminalQueueStatus: 1 });

module.exports = mongoose.model('Driver', driverSchema);
