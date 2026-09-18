const Ride = require('../models/rideSession');

// Partial unloads belong to their actual action date. The final residual covers
// solo legacy records and trip-end completion without counting earlier unloads twice.
const unloadingPipeline = ({ from, to, tripIds }) => [
  { $match: {
    ...(tripIds ? { tripSessionId: { $in: tripIds } } : {}),
    $or: [{ endedAt: { $gte: from, $lte: to } }, { 'unloadMutations.at': { $gte: from, $lte: to } }],
  } },
  { $set: { unloadEvents: { $concatArrays: [
    { $ifNull: ['$unloadMutations', []] },
    { $cond: [{ $eq: ['$status', 'completed'] }, [{
      at: '$endedAt',
      count: { $subtract: [{ $ifNull: ['$boardedCount', 1] }, { $sum: '$unloadMutations.count' }] },
    }], []] },
  ] } } },
  { $unwind: '$unloadEvents' },
  { $match: { 'unloadEvents.at': { $gte: from, $lte: to }, 'unloadEvents.count': { $gt: 0 } } },
  { $set: { endedAt: '$unloadEvents.at', seatCount: '$unloadEvents.count' } },
];

const totalSeats = async (pipeline) => {
  const rows = await Ride.aggregate([...pipeline, { $group: { _id: null, count: { $sum: '$seatCount' } } }]);
  return rows[0]?.count ?? 0;
};
module.exports = { unloadingPipeline, totalSeats };
