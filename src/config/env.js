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
const booleanValue = (value, fallback = false) => {
  if (value == null || String(value).trim() === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).trim().toLowerCase());
};
const positiveInteger = (value, fallback, name) => {
  const parsed = Number(value == null || value === '' ? fallback : value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
};

module.exports = {
  groupBookingsEnabled: booleanValue(process.env.GROUP_BOOKINGS_ENABLED, false),
  nodeEnv: process.env.NODE_ENV || 'development',
  deploymentEnvironment:
    process.env.DEPLOYMENT_ENV || process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 5000),
  mongoUri: required(process.env.MONGO_URI, 'MONGO_URI'),
  jwtSecret: required(process.env.JWT_SECRET, 'JWT_SECRET'),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '15m',
  jwtRefreshSecret: required(process.env.JWT_REFRESH_SECRET, 'JWT_REFRESH_SECRET'),
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
  destinationApproachAlertMeters: Number(
    process.env.DESTINATION_APPROACH_ALERT_METERS || 50
  ),
  jeepPassByReassignMeters: Number(
    process.env.JEEP_PASS_BY_REASSIGN_METERS || 50
  ),
  autoBoardingProximityMeters: Number(
    process.env.AUTO_BOARDING_PROXIMITY_METERS || 25
  ),
  autoBoardingDwellSeconds: Number(
    process.env.AUTO_BOARDING_DWELL_SECONDS || 10
  ),
  autoBoardingPassengerLocationMaxAgeSeconds: Number(
    process.env.AUTO_BOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS || 45
  ),
  autoBoardingDriverLocationMaxAgeSeconds: Number(
    process.env.AUTO_BOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS || 20
  ),
  autoOffboardingDistanceMeters: Number(
    process.env.AUTO_OFFBOARDING_DISTANCE_METERS || 120
  ),
  autoOffboardingConsecutiveOutsideChecks: Number(
    process.env.AUTO_OFFBOARDING_CONSECUTIVE_OUTSIDE_CHECKS || 3
  ),
  autoOffboardingPassengerLocationMaxAgeSeconds: Number(
    process.env.AUTO_OFFBOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS || 15
  ),
  autoOffboardingDriverLocationMaxAgeSeconds: Number(
    process.env.AUTO_OFFBOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS || 15
  ),
  fareBaseAmount: Number(process.env.FARE_BASE_AMOUNT || 17),
  fareBaseDistanceKm: Number(process.env.FARE_BASE_DISTANCE_KM || 4),
  fareAdditionalAmountPerKm: Number(
    process.env.FARE_ADDITIONAL_AMOUNT_PER_KM || 2
  ),

  googleClientIds: splitCsv(process.env.GOOGLE_CLIENT_IDS),
  corsAllowedOrigins: splitCsv(process.env.CORS_ALLOWED_ORIGINS),
  shutdownTimeoutMs: positiveInteger(
    process.env.SHUTDOWN_TIMEOUT_MS,
    15000,
    'SHUTDOWN_TIMEOUT_MS'
  ),
  rateLimitWindowMs: positiveInteger(
    process.env.RATE_LIMIT_WINDOW_MS,
    60000,
    'RATE_LIMIT_WINDOW_MS'
  ),
  rateLimitAuthMax: positiveInteger(
    process.env.RATE_LIMIT_AUTH_MAX,
    30,
    'RATE_LIMIT_AUTH_MAX'
  ),
  rateLimitDriverLocationMax: positiveInteger(
    process.env.RATE_LIMIT_DRIVER_LOCATION_MAX,
    120,
    'RATE_LIMIT_DRIVER_LOCATION_MAX'
  ),
  rateLimitPassengerLocationMax: positiveInteger(
    process.env.RATE_LIMIT_PASSENGER_LOCATION_MAX,
    30,
    'RATE_LIMIT_PASSENGER_LOCATION_MAX'
  ),
  rateLimitEtaMax: positiveInteger(
    process.env.RATE_LIMIT_ETA_MAX,
    12,
    'RATE_LIMIT_ETA_MAX'
  ),
  rateLimitSupportMax: positiveInteger(
    process.env.RATE_LIMIT_SUPPORT_MAX,
    60,
    'RATE_LIMIT_SUPPORT_MAX'
  ),
  rateLimitAdminMax: positiveInteger(
    process.env.RATE_LIMIT_ADMIN_MAX,
    120,
    'RATE_LIMIT_ADMIN_MAX'
  ),
  rateLimitGeneralMax: positiveInteger(
    process.env.RATE_LIMIT_GENERAL_MAX,
    300,
    'RATE_LIMIT_GENERAL_MAX'
  ),
  facebookAppToken: process.env.FACEBOOK_APP_TOKEN || '',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || '',
  firebaseClientEmail: process.env.FIREBASE_CLIENT_EMAIL || '',
  firebasePrivateKey: normalizeMultiline(process.env.FIREBASE_PRIVATE_KEY),
  smsApiPhApiKey: process.env.SMSAPIPH_API_KEY || '',
  smsApiPhBaseUrl: process.env.SMSAPIPH_BASE_URL || 'https://smsapiph.onrender.com/api/v1',
  tomtomApiKey: process.env.TOMTOM_API_KEY || '',
  googleRoutesApiKey: process.env.GOOGLE_ROUTES_API_KEY || '',
  awsRegion: process.env.AWS_REGION || 'ap-southeast-1',
  driverDocumentsBucket: process.env.DRIVER_DOCUMENTS_BUCKET || '',
  redisUrl: process.env.REDIS_URL || '',
  redisNamespace:
    process.env.REDIS_NAMESPACE ||
    `parago:${process.env.DEPLOYMENT_ENV || process.env.NODE_ENV || 'development'}:v1`,
  redisConnectTimeoutMs: Number(process.env.REDIS_CONNECT_TIMEOUT_MS || 3000),
  redisLatestLocationTtlSeconds: Number(
    process.env.REDIS_LATEST_LOCATION_TTL_SECONDS || 60
  ),
  redisActiveContextTtlSeconds: Number(
    process.env.REDIS_ACTIVE_CONTEXT_TTL_SECONDS || 45
  ),
  runApiJobs: booleanValue(process.env.RUN_API_JOBS, true),
  runWorkerJobs: booleanValue(process.env.RUN_WORKER_JOBS, false),
  asyncLocationProcessingEnabled: booleanValue(
    process.env.ASYNC_LOCATION_PROCESSING_ENABLED,
    false
  ),
  workerLocationFlushIntervalMs: Number(
    process.env.WORKER_LOCATION_FLUSH_INTERVAL_MS || 5000
  ),
  workerAutomationPollIntervalMs: Number(
    process.env.WORKER_AUTOMATION_POLL_INTERVAL_MS || 1000
  ),
  workerMaxBatchSize: Number(process.env.WORKER_MAX_BATCH_SIZE || 500),
  workerMaxAttempts: Number(process.env.WORKER_MAX_ATTEMPTS || 5),
  workerFailedJobRetention: Number(
    process.env.WORKER_FAILED_JOB_RETENTION || 1000
  ),
};

if (module.exports.nodeEnv === 'production') {
  if (isPlaceholder(module.exports.jwtSecret) || isPlaceholder(module.exports.jwtRefreshSecret)) {
    throw new Error('JWT secrets must be replaced before production deployment');
  }
  if (
    module.exports.redisUrl &&
    !module.exports.redisUrl.toLowerCase().startsWith('rediss://')
  ) {
    throw new Error('Production REDIS_URL must use rediss:// TLS');
  }
  if (module.exports.corsAllowedOrigins.length === 0) {
    throw new Error('Production CORS_ALLOWED_ORIGINS must not be empty');
  }
  if (module.exports.corsAllowedOrigins.includes('*')) {
    throw new Error('Production CORS_ALLOWED_ORIGINS cannot contain a wildcard');
  }
}

if (module.exports.runApiJobs && module.exports.runWorkerJobs) {
  throw new Error('RUN_API_JOBS and RUN_WORKER_JOBS cannot both be enabled');
}

if (
  module.exports.asyncLocationProcessingEnabled &&
  !module.exports.redisUrl
) {
  throw new Error('ASYNC_LOCATION_PROCESSING_ENABLED requires REDIS_URL');
}

if (module.exports.jwtSecret === module.exports.jwtRefreshSecret) {
  throw new Error('Access and refresh signing secrets must differ');
}
if (['staging', 'production'].includes(module.exports.deploymentEnvironment) && module.exports.nodeEnv !== 'production') {
  throw new Error('Deployed staging/production requires NODE_ENV=production');
}
