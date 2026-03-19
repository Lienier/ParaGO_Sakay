const mongoose = require('mongoose');
const { mongoUri } = require('./env');
const User = require('../models/user');

let isConnected = false;

const syncCriticalIndexes = async () => {
  await User.collection.updateMany(
    { providerId: { $in: [null, ''] } },
    { $unset: { providerId: '' } }
  );
  await User.syncIndexes();
};

const connectDb = async () => {
  if (isConnected) return;

  try {
    await mongoose.connect(mongoUri, {
      autoIndex: true,
      serverSelectionTimeoutMS: 12000,
    });
    await syncCriticalIndexes();
    isConnected = true;
    // eslint-disable-next-line no-console
    console.log('Connected to MongoDB Atlas');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('MongoDB connection failed:', error.message);
    throw error;
  }
};

module.exports = connectDb;
