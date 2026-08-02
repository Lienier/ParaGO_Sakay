const assert = require('node:assert/strict');
const { afterEach, test } = require('node:test');

const {
  validateStagingBoundary,
  applyStagingEnvironment,
  applyPortArgument,
} = require('../scripts/start-staging');

const productionUri =
  'mongodb+srv://user:password@production.example.mongodb.net/parago';
const stagingUri =
  'mongodb+srv://user:password@staging.example.mongodb.net/parago_staging';

const originalEnvironment = {
  MONGO_URI: process.env.MONGO_URI,
  JWT_SECRET: process.env.JWT_SECRET,
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET,
  GOOGLE_ROUTES_API_KEY: process.env.GOOGLE_ROUTES_API_KEY,
  PORT: process.env.PORT,
};

afterEach(() => {
  for (const [key, value] of Object.entries(originalEnvironment)) {
    if (value == null) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
});

test('staging boundary accepts a separate Atlas host and staging database', () => {
  const result = validateStagingBoundary({ productionUri, stagingUri });
  assert.equal(result.production.database, 'parago');
  assert.equal(result.staging.database, 'parago_staging');
  assert.notEqual(result.production.host, result.staging.host);
});

test('staging boundary refuses production URI reuse', () => {
  assert.throws(
    () =>
      validateStagingBoundary({
        productionUri,
        stagingUri: productionUri,
      }),
    /URIs match/
  );
});

test('staging boundary refuses the wrong database or shared Atlas host', () => {
  assert.throws(
    () =>
      validateStagingBoundary({
        productionUri,
        stagingUri:
          'mongodb+srv://user:password@staging.example.mongodb.net/parago',
      }),
    /not parago_staging/
  );
  assert.throws(
    () =>
      validateStagingBoundary({
        productionUri,
        stagingUri:
          'mongodb+srv://user:password@production.example.mongodb.net/parago_staging',
      }),
    /hosts match/
  );
});

test('staging environment overrides database and external service credentials', () => {
  process.env.GOOGLE_ROUTES_API_KEY = 'production-key';
  const result = applyStagingEnvironment({
    productionValues: { MONGO_URI: productionUri },
    stagingValues: { STAGING_MONGO_URI: stagingUri },
  });

  assert.equal(process.env.MONGO_URI, stagingUri);
  assert.equal(process.env.GOOGLE_ROUTES_API_KEY, '');
  assert.ok(process.env.JWT_SECRET.length >= 64);
  assert.ok(process.env.JWT_REFRESH_SECRET.length >= 64);
  assert.equal(result.database, 'parago_staging');
  assert.equal(result.usesEphemeralJwt, true);
});

test('staging port accepts an explicit safe port and rejects malformed values', () => {
  assert.equal(applyPortArgument(['--port=5001']), 5001);
  assert.equal(process.env.PORT, '5001');
  assert.throws(() => applyPortArgument(['--port=80']), /between 1024 and 65535/);
  assert.throws(
    () => applyPortArgument(['--port=not-a-port']),
    /between 1024 and 65535/
  );
});
