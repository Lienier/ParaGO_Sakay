const mongoose = require('mongoose');
module.exports = mongoose.model('MobileReleasePolicy', new mongoose.Schema({
  _id: { type: String, enum: ['driver', 'passenger'] },
  latestBuild: { type: Number, default: 0 },
  minimumBuild: { type: Number, default: 0 },
  revision: { type: Number, default: 0 },
  message: { type: String, maxlength: 500, default: '' },
}, { timestamps: true }));
