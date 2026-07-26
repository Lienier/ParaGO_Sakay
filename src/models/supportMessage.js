const mongoose = require('mongoose');

const { Schema } = mongoose;

const supportMessageSchema = new Schema(
  {
    threadId: {
      type: Schema.Types.ObjectId,
      ref: 'SupportThread',
      required: true,
      index: true,
    },
    senderId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    senderRole: {
      type: String,
      enum: ['PASSENGER', 'DRIVER', 'ADMIN'],
      required: true,
    },
    body: { type: String, required: true, trim: true },
  },
  { timestamps: true }
);

supportMessageSchema.index({ threadId: 1, createdAt: 1 });
supportMessageSchema.index({ senderId: 1, createdAt: -1 });

module.exports = mongoose.model('SupportMessage', supportMessageSchema);
