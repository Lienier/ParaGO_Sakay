const mongoose = require('mongoose');

const { Schema } = mongoose;

const announcementSchema = new Schema(
  {
    title: { type: String, required: true, trim: true, maxlength: 160 },
    body: { type: String, required: true, trim: true, maxlength: 5000 },
    category: {
      type: String,
      required: true,
      enum: ['service_change', 'disruption', 'maintenance', 'safety', 'general'],
    },
    severity: {
      type: String,
      required: true,
      enum: ['info', 'warning', 'critical'],
    },
    audiences: {
      type: [{ type: String, enum: ['PASSENGER', 'DRIVER'] }],
      required: true,
      validate: {
        validator: (values) => Array.isArray(values) && values.length > 0,
        message: 'At least one audience is required',
      },
    },
    status: {
      type: String,
      required: true,
      enum: ['scheduled', 'published', 'expired', 'archived'],
      index: true,
    },
    revision: { type: Number, min: 1, default: 1 },
    startsAt: { type: Date, required: true },
    expiresAt: { type: Date },
    publishedAt: { type: Date },
    archivedAt: { type: Date },
    createdByAdminId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    updatedByAdminId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    archivedByAdminId: { type: Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

announcementSchema.index({ audiences: 1, status: 1, startsAt: -1 });
announcementSchema.index({ status: 1, startsAt: 1, expiresAt: 1 });

module.exports = mongoose.model('Announcement', announcementSchema);
