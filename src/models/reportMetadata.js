const mongoose = require('mongoose');

const { Schema } = mongoose;

const reportMetadataSchema = new Schema(
  {
    reportType: { type: String, required: true, trim: true },
    periodStart: { type: Date, required: true },
    periodEnd: { type: Date, required: true },
    generatedBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    params: { type: Schema.Types.Mixed, default: {} },
    resultSummary: { type: Schema.Types.Mixed, default: {} },
    fileUrl: { type: String },
  },
  { timestamps: true }
);

reportMetadataSchema.index({ reportType: 1, periodStart: 1, periodEnd: 1 });

module.exports = mongoose.model('ReportMetadata', reportMetadataSchema);
