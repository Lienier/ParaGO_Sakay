const Jeepney = require('../models/jeepney');
const TripSession = require('../models/tripSession');
const {
  getOrLoadDriverActiveContext,
  invalidateDriverActiveContext,
} = require('./transientState.service');

const resolveFromMongo = async (driver) => {
  let jeepneyId = driver.assignedJeepneyId || null;
  if (!jeepneyId) {
    const linkedJeepney = await Jeepney.findOne({
      currentDriverId: driver._id,
    })
      .select('_id')
      .sort({ updatedAt: -1, createdAt: -1 });
    jeepneyId = linkedJeepney?._id || null;
  }

  let trip = await TripSession.findOne({
    driverId: driver._id,
    status: 'active',
    ...(jeepneyId ? { jeepneyId } : {}),
  })
    .select('_id jeepneyId routeId status')
    .sort({ createdAt: -1 });
  if (!jeepneyId && trip?.jeepneyId) {
    jeepneyId = trip.jeepneyId;
  }

  if (!trip && !jeepneyId) {
    trip = await TripSession.findOne({
      driverId: driver._id,
      status: { $in: ['active', 'scheduled'] },
    })
      .select('_id jeepneyId routeId status')
      .sort({ status: 1, createdAt: -1 });
    jeepneyId = trip?.jeepneyId || null;
  }

  if (!jeepneyId) return null;
  return {
    driverId: String(driver._id),
    jeepneyId: String(jeepneyId),
    tripId: trip?._id ? String(trip._id) : null,
    routeId: trip?.routeId ? String(trip.routeId) : null,
    tripStatus: trip?.status || null,
  };
};

const resolveDriverActiveContext = async (driver) =>
  getOrLoadDriverActiveContext({
    driverId: driver._id,
    loader: () => resolveFromMongo(driver),
  });

module.exports = {
  resolveFromMongo,
  resolveDriverActiveContext,
  invalidateDriverActiveContext,
};
