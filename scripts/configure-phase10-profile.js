const fs = require('fs');
const mongoose = require('mongoose');

const TripSession = require('../src/models/tripSession');
const {
  loadManifestPath,
  loadStagingBoundary,
  positiveInteger,
} = require('./phase10-safety');

const syntheticTripNote = 'Phase 10 synthetic capacity trip.';

const parseArguments = (args) => {
  const values = {};
  for (const argument of args) {
    if (!argument.startsWith('--') || !argument.includes('=')) continue;
    const separator = argument.indexOf('=');
    values[argument.slice(2, separator)] = argument.slice(separator + 1);
  }
  return values;
};

const partitionTripIds = (drivers, activeDriverCount) => ({
  activeTripIds: drivers
    .slice(0, activeDriverCount)
    .map((entry) => entry.tripId),
  inactiveTripIds: drivers
    .slice(activeDriverCount)
    .map((entry) => entry.tripId),
});

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const manifest = JSON.parse(fs.readFileSync(loadManifestPath, 'utf8'));
  if (
    manifest.environment !== 'staging' ||
    manifest.database !== 'parago_staging' ||
    !Array.isArray(manifest.drivers) ||
    !manifest.routeId
  ) {
    throw new Error('Synthetic staging manifest is invalid');
  }
  const activeDriverCount = positiveInteger(
    args.drivers,
    'drivers',
    manifest.drivers.length
  );
  const { stagingUri } = loadStagingBoundary();
  const allTripIds = manifest.drivers.map((entry) => entry.tripId);
  if (allTripIds.some((id) => !mongoose.isValidObjectId(id))) {
    throw new Error('Synthetic staging manifest contains an invalid trip id');
  }

  await mongoose.connect(stagingUri, {
    autoIndex: false,
    dbName: 'parago_staging',
    serverSelectionTimeoutMS: 10000,
  });

  const matched = await TripSession.countDocuments({
    _id: { $in: allTripIds },
    routeId: manifest.routeId,
    notes: syntheticTripNote,
  });
  if (matched !== allTripIds.length) {
    throw new Error(
      `Refusing profile update: expected ${allTripIds.length} verified synthetic trips, found ${matched}`
    );
  }

  const { activeTripIds, inactiveTripIds } = partitionTripIds(
    manifest.drivers,
    activeDriverCount
  );
  await TripSession.updateMany(
    { _id: { $in: activeTripIds }, notes: syntheticTripNote },
    {
      $set: {
        status: 'active',
        active: true,
        acceptRequests: true,
        startedAt: new Date(),
      },
      $unset: { endedAt: '' },
    }
  );
  if (inactiveTripIds.length > 0) {
    await TripSession.updateMany(
      { _id: { $in: inactiveTripIds }, notes: syntheticTripNote },
      {
        $set: {
          status: 'scheduled',
          active: false,
          acceptRequests: false,
        },
        $unset: { startedAt: '', endedAt: '' },
      }
    );
  }

  console.log(
    `Phase 10 profile ready: ${activeDriverCount} active synthetic drivers, ${inactiveTripIds.length} inactive synthetic drivers.`
  );
  console.log('No production records or non-synthetic staging trips were modified.');
}

if (require.main === module) {
  main()
    .catch((error) => {
      console.error(`Phase 10 profile configuration failed: ${error.message}`);
      process.exitCode = 1;
    })
    .finally(async () => {
      await mongoose.disconnect().catch(() => {});
    });
}

module.exports = { parseArguments, partitionTripIds, syntheticTripNote };
