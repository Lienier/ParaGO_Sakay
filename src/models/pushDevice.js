const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  sessionId: { type: String, required: true, unique: true },
  userId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
  token: { type: String, required: true, unique: true, select: false },
}, { timestamps: true });
module.exports = mongoose.model('PushDevice', schema);
