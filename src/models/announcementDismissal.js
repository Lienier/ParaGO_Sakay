const mongoose = require('mongoose');

const { Schema } = mongoose;

const announcementDismissalSchema = new Schema(
  {
    announcementId: {
      type: Schema.Types.ObjectId,
      ref: 'Announcement',
      required: true,
    },
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    revision: { type: Number, min: 1, required: true },
    dismissedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

announcementDismissalSchema.index(
  { announcementId: 1, userId: 1, revision: 1 },
  { unique: true }
);
announcementDismissalSchema.index({ userId: 1, dismissedAt: -1 });

module.exports = mongoose.model(
  'AnnouncementDismissal',
  announcementDismissalSchema
);
