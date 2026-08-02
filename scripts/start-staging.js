const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');

const readEnvironmentFile = (filePath) => {
  const values = {};
  for (const rawLine of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const separator = line.indexOf('=');
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
};

const parseMongoTarget = (uri, label, { requireSrv = false } = {}) => {
  const value = String(uri || '').trim();
  if (!/^mongodb(?:\+srv)?:\/\//i.test(value)) {
    throw new Error(`${label} must use a MongoDB URI`);
  }
  if (requireSrv && !value.startsWith('mongodb+srv://')) {
    throw new Error(`${label} must use an Atlas mongodb+srv URI`);
  }

  const withoutScheme = value.replace(/^mongodb(?:\+srv)?:\/\//i, '');
  const pathSeparator = withoutScheme.indexOf('/');
  if (pathSeparator < 0) {
    throw new Error(`${label} must include a MongoDB host and database`);
  }
  const authority = withoutScheme.slice(0, pathSeparator);
  const host = authority.slice(authority.lastIndexOf('@') + 1).toLowerCase();
  const database = decodeURIComponent(
    withoutScheme.slice(pathSeparator + 1).split('?')[0]
  );
  if (!host || !database) {
    throw new Error(`${label} must include a MongoDB host and database`);
  }
  return {
    host,
    database,
  };
};

const validateStagingBoundary = ({ productionUri, stagingUri }) => {
  if (!productionUri) {
    throw new Error('Production MONGO_URI is unavailable for boundary checks');
  }
  if (!stagingUri) {
    throw new Error('STAGING_MONGO_URI is required');
  }
  if (productionUri === stagingUri) {
    throw new Error('Refusing to start: staging and production URIs match');
  }

  const production = parseMongoTarget(productionUri, 'Production MONGO_URI');
  const staging = parseMongoTarget(stagingUri, 'STAGING_MONGO_URI', {
    requireSrv: true,
  });
  if (staging.database !== 'parago_staging') {
    throw new Error(
      `Refusing to start: staging database is ${staging.database}, not parago_staging`
    );
  }
  if (production.host === staging.host) {
    throw new Error('Refusing to start: staging and production Atlas hosts match');
  }
  return { production, staging };
};

const fingerprint = (value) =>
  crypto.createHash('sha256').update(value).digest('hex').slice(0, 12);

const applyStagingEnvironment = ({ productionValues, stagingValues }) => {
  const productionUri = productionValues.MONGO_URI;
  const stagingUri = stagingValues.STAGING_MONGO_URI;
  const targets = validateStagingBoundary({ productionUri, stagingUri });

  process.env.NODE_ENV = 'development';
  process.env.MONGO_URI = stagingUri;
  process.env.JWT_SECRET =
    stagingValues.STAGING_JWT_SECRET || crypto.randomBytes(48).toString('hex');
  process.env.JWT_REFRESH_SECRET =
    stagingValues.STAGING_JWT_REFRESH_SECRET ||
    crypto.randomBytes(48).toString('hex');
  process.env.GOOGLE_ROUTES_API_KEY = '';
  process.env.TOMTOM_API_KEY = '';
  process.env.FIREBASE_PROJECT_ID = '';
  process.env.FIREBASE_CLIENT_EMAIL = '';
  process.env.FIREBASE_PRIVATE_KEY = '';
  process.env.SMSAPIPH_API_KEY = '';
  process.env.CORS_ALLOWED_ORIGINS = '';
  process.env.DEPLOYMENT_ENV = 'staging';
  process.env.REDIS_URL = stagingValues.STAGING_REDIS_URL || '';
  process.env.REDIS_NAMESPACE =
    stagingValues.STAGING_REDIS_NAMESPACE || 'parago:staging:v1';

  return {
    database: targets.staging.database,
    host: targets.staging.host,
    fingerprint: fingerprint(stagingUri),
    usesEphemeralJwt:
      !stagingValues.STAGING_JWT_SECRET ||
      !stagingValues.STAGING_JWT_REFRESH_SECRET,
  };
};

const applyPortArgument = (args = process.argv.slice(2)) => {
  const raw = args.find((value) => value.startsWith('--port='));
  if (!raw) return null;
  const port = Number(raw.slice('--port='.length));
  if (!Number.isSafeInteger(port) || port < 1024 || port > 65535) {
    throw new Error('Staging port must be an integer between 1024 and 65535');
  }
  process.env.PORT = String(port);
  return port;
};

const start = () => {
  applyPortArgument();
  const productionValues = readEnvironmentFile(path.join(rootDir, '.env'));
  const stagingValues = readEnvironmentFile(
    path.join(rootDir, '.env.staging')
  );
  const target = applyStagingEnvironment({
    productionValues,
    stagingValues,
  });
  console.log(
    `[Staging Guard] target=${target.database} host=${target.host} ` +
      `fingerprint=${target.fingerprint} ephemeralJwt=${target.usesEphemeralJwt}`
  );
  require('../src/server');
};

if (require.main === module) {
  try {
    start();
  } catch (error) {
    console.error(`[Staging Guard] ${error.message}`);
    process.exit(1);
  }
}

module.exports = {
  readEnvironmentFile,
  parseMongoTarget,
  validateStagingBoundary,
  applyStagingEnvironment,
  applyPortArgument,
};
