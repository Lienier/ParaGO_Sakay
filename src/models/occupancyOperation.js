const mongoose = require('mongoose');

// Retain operation receipts for the trip's lifetime: delayed retries must never
// apply a second adjustment, even after an app restart.
const schema = new mongoose.Schema({
  _id: String,
  tripId: { type: mongoose.Schema.Types.ObjectId, required: true },
  driverId: { type: mongoose.Schema.Types.ObjectId, required: true },
  delta: { type: Number, required: true },
}, { timestamps: true });
module.exports = mongoose.model('OccupancyOperation', schema);
