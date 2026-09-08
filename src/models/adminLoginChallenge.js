const mongoose = require('mongoose');

const { Schema } = mongoose;

const adminLoginChallengeSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    email: { type: String, required: true, trim: true },
    codeHash: { type: String, required: true },
    expiresAt: { type: Date, required: true },
    attempts: { type: Number, default: 0 },
    maxAttempts: { type: Number, default: 5 },
    usedAt: { type: Date, default: null, index: true },
  },
  { timestamps: true }
);

adminLoginChallengeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
adminLoginChallengeSchema.index({ userId: 1, usedAt: 1, createdAt: -1 });

module.exports = mongoose.model('AdminLoginChallenge', adminLoginChallengeSchema);
