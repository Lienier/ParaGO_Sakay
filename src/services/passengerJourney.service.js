const Passenger = require('../models/passenger');
const Ride = require('../models/rideSession');
const Pickup = require('../models/pickupRequest');
const ApiError = require('../utils/apiError');

async function lockPassenger(passengerId, session) {
  const passenger = await Passenger.findOneAndUpdate({ _id: passengerId },
    { $inc: { journeyRevision: 1 } }, { new: true, session });
  if (!passenger) throw new ApiError(404, 'Passenger not found');
}

async function assertCanBook(passengerId, session, excludingRequestId) {
  if (await Ride.exists({ passengerId, status: { $in: ['waiting', 'onboard'] } }).session(session)) {
    throw new ApiError(409, 'You already have an active ride');
  }
  if (await Pickup.exists({ passengerId,
    ...(excludingRequestId ? { _id: { $ne: excludingRequestId } } : {}),
    status: { $in: ['pending', 'acknowledged', 'transfer_offered'] },
    expiresAt: { $gt: new Date() },
  }).session(session)) throw new ApiError(409, 'You already have a pickup request or pending transfer offer');
}
module.exports = { lockPassenger, assertCanBook };
