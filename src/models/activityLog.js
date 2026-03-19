const mongoose = require('mongoose');

const { Schema } = mongoose;

const activityLogSchema = new Schema(
  {
    actorId: { type: Schema.Types.ObjectId, ref: 'User' },
    actorRole: { type: String, trim: true },
    action: { type: String, required: true, trim: true },
    entity: { type: String, required: true, trim: true },
    entityId: { type: String, trim: true },
    details: { type: Schema.Types.Mixed, default: {} },
    ip: { type: String },
    client: { type: String },
  },
  { timestamps: true }
);

activityLogSchema.index({ actorId: 1, createdAt: -1 });
activityLogSchema.index({ entity: 1, entityId: 1, createdAt: -1 });

module.exports = mongoose.model('ActivityLog', activityLogSchema);
