const dotenv = require('dotenv');

dotenv.config();

const required = (value, name) => {
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
};

const isPlaceholder = (value) => /^replace_with_/i.test(String(value || '').trim());

const splitCsv = (value) =>
  (value || '')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean);

const normalizeMultiline = (value) => String(value || '').replace(/\\n/g, '\n').trim();

module.exports = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 5000),
  mongoUri: required(process.env.MONGO_URI, 'MONGO_URI'),
  jwtSecret: required(process.env.JWT_SECRET, 'JWT_SECRET'),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  jwtRefreshSecret: process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET,
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',

  boardingWindowMinutes: Number(process.env.BOARDING_WINDOW_MINUTES || 10),
  stopAlertCooldownMinutes: Number(process.env.STOP_ALERT_COOLDOWN_MINUTES || 2),
  stopAlertRoadProximityMeters: Number(
    process.env.STOP_ALERT_ROAD_PROXIMITY_METERS || 300
  ),
  unloadRoadProximityMeters: Number(
    process.env.UNLOAD_ROAD_PROXIMITY_METERS || 5
  ),
  pickupRequestTtlMinutes: Number(process.env.PICKUP_REQUEST_TTL_MINUTES || 12),
  maxRequestsPerPassengerPerTrip: Number(
    process.env.MAX_REQUESTS_PER_PASSENGER_PER_TRIP || 2
  ),
  pickupRoadProximityMeters: Number(process.env.PICKUP_ROAD_PROXIMITY_METERS || 300),
  pickupCurrentLocationMaxDistanceMeters: Number(
    process.env.PICKUP_CURRENT_LOCATION_MAX_DISTANCE_METERS || 50
  ),
  jeepPassByReassignMeters: Number(
    process.env.JEEP_PASS_BY_REASSIGN_METERS || 50
  ),
  fareBaseAmount: Number(process.env.FARE_BASE_AMOUNT || 17),
  fareBaseDistanceKm: Number(process.env.FARE_BASE_DISTANCE_KM || 4),
  fareAdditionalAmountPerKm: Number(
    process.env.FARE_ADDITIONAL_AMOUNT_PER_KM || 2
  ),

  googleClientIds: splitCsv(process.env.GOOGLE_CLIENT_IDS),
  facebookAppToken: process.env.FACEBOOK_APP_TOKEN || '',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || '',
  firebaseClientEmail: process.env.FIREBASE_CLIENT_EMAIL || '',
  firebasePrivateKey: normalizeMultiline(process.env.FIREBASE_PRIVATE_KEY),
  smsApiPhApiKey: process.env.SMSAPIPH_API_KEY || '',
  smsApiPhBaseUrl: process.env.SMSAPIPH_BASE_URL || 'https://smsapiph.onrender.com/api/v1',
  tomtomApiKey: process.env.TOMTOM_API_KEY || '',
};

if (module.exports.nodeEnv === 'production') {
  if (isPlaceholder(module.exports.jwtSecret) || isPlaceholder(module.exports.jwtRefreshSecret)) {
    throw new Error('JWT secrets must be replaced before production deployment');
  }
}
