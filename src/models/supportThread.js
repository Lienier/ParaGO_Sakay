const mongoose = require('mongoose');

const { Schema } = mongoose;

const supportThreadSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    userRole: {
      type: String,
      enum: ['PASSENGER', 'DRIVER'],
      required: true,
    },
    assignedAdminId: { type: Schema.Types.ObjectId, ref: 'User' },
    subject: { type: String, trim: true, default: '' },
    category: {
      type: String,
      enum: [
        'complaint',
        'lost_item',
        'fare_concern',
        'trip_issue',
        'safety_concern',
        'general_help',
      ],
      default: 'general_help',
    },
    status: {
      type: String,
      enum: ['open', 'awaiting_admin', 'awaiting_user', 'resolved', 'closed'],
      default: 'open',
    },
    tripSessionId: { type: Schema.Types.ObjectId, ref: 'TripSession' },
    pickupRequestId: { type: Schema.Types.ObjectId, ref: 'PickupRequest' },
    rideSessionId: { type: Schema.Types.ObjectId, ref: 'RideSession' },
    routeId: { type: Schema.Types.ObjectId, ref: 'Route' },
    lastMessageAt: { type: Date },
    lastMessagePreview: { type: String, trim: true },
    lastMessageSenderRole: {
      type: String,
      enum: ['PASSENGER', 'DRIVER', 'ADMIN'],
    },
    unreadAdminCount: { type: Number, min: 0, default: 0 },
    unreadUserCount: { type: Number, min: 0, default: 0 },
    lastUserReadAt: { type: Date },
    lastAdminReadAt: { type: Date },
    resolvedAt: { type: Date },
    resolvedByUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    closedAt: { type: Date },
    closedByUserId: { type: Schema.Types.ObjectId, ref: 'User' },
    reopenedAt: { type: Date },
    reopenedByUserId: { type: Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

supportThreadSchema.index({ userId: 1, createdAt: -1 });
supportThreadSchema.index({ status: 1, lastMessageAt: -1 });
supportThreadSchema.index({ assignedAdminId: 1, status: 1, lastMessageAt: -1 });
supportThreadSchema.index({ routeId: 1, status: 1, lastMessageAt: -1 });

module.exports = mongoose.model('SupportThread', supportThreadSchema);
