const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  _id: { type: mongoose.Schema.Types.ObjectId, ref: 'Route' },
  revision: { type: Number, default: 0 },
  nextPosition: { type: Number, default: 0 },
}, { timestamps: true });
module.exports = mongoose.model('TerminalQueue', schema);
