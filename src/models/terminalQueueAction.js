const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  routeId: { type: mongoose.Schema.Types.ObjectId, required: true },
  tripId: { type: mongoose.Schema.Types.ObjectId, required: true },
  actorId: { type: mongoose.Schema.Types.ObjectId },
  actorRole: { type: String, required: true },
  action: { type: String, required: true },
  reason: String,
  requestId: { type: String, required: true },
}, { timestamps: true });
schema.index({ actorId: 1, requestId: 1 }, { unique: true });
module.exports = mongoose.model('TerminalQueueAction', schema);
