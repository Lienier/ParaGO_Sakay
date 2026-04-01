const fs = require('fs');
const path = require('path');
const axios = require('axios');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const readArg = (name) => {
  const index = process.argv.indexOf(name);
  if (index === -1 || index === process.argv.length - 1) {
    return null;
  }
  return process.argv[index + 1];
};

const requireArg = (name) => {
  const value = readArg(name);
  if (!value) {
    throw new Error(`Missing required argument: ${name}`);
  }
  return value;
};

const readArgs = (name) => {
  const values = [];
  for (let index = 0; index < process.argv.length; index += 1) {
    if (process.argv[index] === name && index < process.argv.length - 1) {
      values.push(process.argv[index + 1]);
    }
  }
  return values;
};

const parseLatLng = (value, name) => {
  const [latText, lngText] = String(value)
    .split(',')
    .map((entry) => entry.trim());
  const lat = Number(latText);
  const lng = Number(lngText);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new Error(`${name} must be formatted as "lat,lng"`);
  }
  return { lat, lng };
};

const sampleCoordinates = (coordinates, targetCount = 24) => {
  if (!Array.isArray(coordinates) || coordinates.length <= targetCount) {
    return coordinates || [];
  }

  const step = Math.max(1, Math.floor(coordinates.length / targetCount));
  const sampled = [];
  for (let index = 0; index < coordinates.length; index += step) {
    sampled.push(coordinates[index]);
  }

  const last = coordinates[coordinates.length - 1];
  const currentLast = sampled[sampled.length - 1];
  if (!currentLast || currentLast[0] !== last[0] || currentLast[1] !== last[1]) {
    sampled.push(last);
  }

  return sampled;
};

const main = async () => {
  const orsKey = process.env.ORS_API_KEY;
  if (!orsKey) {
    throw new Error('ORS_API_KEY is required in the root .env');
  }

  const name = requireArg('--name');
  const code = requireArg('--code');
  const start = parseLatLng(requireArg('--start'), '--start');
  const end = parseLatLng(requireArg('--end'), '--end');
  const viaPoints = readArgs('--via').map((value, index) =>
    parseLatLng(value, `--via[${index}]`)
  );
  const direction = readArg('--direction') || 'down';
  const outFile = readArg('--out');

  const response = await axios.post(
    'https://api.openrouteservice.org/v2/directions/driving-car/geojson',
    {
      coordinates: [
        [start.lng, start.lat],
        ...viaPoints.map((point) => [point.lng, point.lat]),
        [end.lng, end.lat],
      ],
      instructions: false,
    },
    {
      headers: {
        Authorization: orsKey,
        'Content-Type': 'application/json',
      },
      timeout: 30000,
    }
  );

  const route = response.data?.features?.[0];
  const coordinates = route?.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    throw new Error('No route geometry returned by OpenRouteService');
  }

  const sampledWaypoints = sampleCoordinates(coordinates).map((entry, index) => ({
    name: `Waypoint ${index + 1}`,
    location: {
      type: 'Point',
      coordinates: entry,
    },
  }));

  const payload = {
    name,
    code,
    direction,
    status: 'active',
    description: `Permanent jeepney route for ${name}.`,
    path: {
      type: 'LineString',
      coordinates,
    },
    waypoints: sampledWaypoints,
    stops: [],
  };

  const output = JSON.stringify(payload, null, 2);
  if (outFile) {
    const target = path.resolve(process.cwd(), outFile);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, `${output}\n`, 'utf8');
    console.log(`Route payload written to ${target}`);
    return;
  }

  console.log(output);
};

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
