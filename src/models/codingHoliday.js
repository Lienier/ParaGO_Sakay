const mongoose = require('mongoose');
module.exports = mongoose.model('CodingHoliday', new mongoose.Schema({
  date: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  updatedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
}, { timestamps: true }));
