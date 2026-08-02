const mongoose = require('mongoose');
const { mongoUri } = require('./env');

let isConnected = false;

const connectDb = async () => {
  if (isConnected && mongoose.connection.readyState === 1) return;

  try {
    await mongoose.connect(mongoUri, {
      autoIndex: false,
      serverSelectionTimeoutMS: 12000,
    });
    isConnected = true;
    // eslint-disable-next-line no-console
    console.log('Connected to MongoDB Atlas');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('MongoDB connection failed:', error.message);
    throw error;
  }
};

const disconnectDb = async () => {
  if (mongoose.connection.readyState !== 0) {
    await mongoose.disconnect();
  }
  isConnected = false;
};

module.exports = connectDb;
module.exports.disconnectDb = disconnectDb;
