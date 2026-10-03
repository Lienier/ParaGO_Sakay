const mongoose = require('mongoose');

const { Schema } = mongoose;

const userSchema = new Schema(
  {
    authVersion: { type: Number, default: 0, select: false },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, select: false },
    fullName: { type: String, required: true, trim: true },
    phone: { type: String, trim: true },
    role: {
      type: String,
      enum: ['PASSENGER', 'DRIVER', 'ADMIN'],
      default: 'PASSENGER',
      uppercase: true,
      trim: true,
    },
    authProvider: {
      type: String,
      enum: ['local', 'google', 'facebook'],
      default: 'local',
    },
    providerId: {
      type: String,
      set: (value) => {
        const normalized = String(value || '').trim();
        return normalized || undefined;
      },
    },
    status: {
      type: String,
      enum: ['active', 'suspended', 'deactivated'],
      default: 'active',
    },
    isVerified: { type: Boolean, default: false },
    lastLoginAt: { type: Date },
    legalAcceptance: {
      termsVersion: { type: String, trim: true },
      privacyVersion: { type: String, trim: true },
      acceptedAt: { type: Date },
    },
  },
  { timestamps: true }
);

userSchema.index({ role: 1, status: 1 });
userSchema.index(
  { authProvider: 1, providerId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      providerId: { $exists: true, $type: 'string' },
    },
  }
);

module.exports = mongoose.model('User', userSchema);
