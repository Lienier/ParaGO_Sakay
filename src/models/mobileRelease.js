const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  app: { type: String, enum: ['driver', 'passenger'], required: true },
  build: { type: Number, required: true, min: 1 },
  version: { type: String, required: true },
  packageName: { type: String, required: true },
  certificate: { type: String, required: true },
  sha256: { type: String, required: true },
  size: { type: Number, required: true },
  objectKey: { type: String, required: true },
  url: { type: String, required: true },
  notes: { type: String, maxlength: 2000, default: '' },
  publishedAt: { type: Date, default: null },
}, { timestamps: true });
schema.index({ app: 1, build: 1 }, { unique: true });
module.exports = mongoose.model('MobileRelease', schema);
