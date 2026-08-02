const fs = require('fs');
const path = require('path');

const { parseMongoTarget, validateStagingBoundary } = require('./start-staging');

const rootDir = path.resolve(__dirname, '..');
const secureDirectory = path.join(rootDir, '.secure-backups');
const loadManifestPath = path.join(
  secureDirectory,
  'phase10-load-manifest.json'
);

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

const loadStagingBoundary = () => {
  const productionPath = path.join(rootDir, '.env');
  const stagingPath = path.join(rootDir, '.env.staging');
  if (!fs.existsSync(productionPath) || !fs.existsSync(stagingPath)) {
    throw new Error('Both ignored .env and .env.staging files are required');
  }
  const production = readEnvironmentFile(productionPath);
  const staging = readEnvironmentFile(stagingPath);
  const productionUri = production.MONGO_URI || production.MONGODB_URI;
  const stagingUri = staging.STAGING_MONGO_URI;
  const targets = validateStagingBoundary({ productionUri, stagingUri });
  return { production, staging, stagingUri, targets };
};

const validateStagingBaseUrl = (value) => {
  const parsed = new URL(String(value || '').trim());
  if (
    parsed.protocol !== 'https:' &&
    parsed.hostname !== '127.0.0.1' &&
    parsed.hostname !== 'localhost'
  ) {
    throw new Error('Phase 10 target must use HTTPS unless it is localhost');
  }
  const host = parsed.hostname.toLowerCase();
  if (
    host.includes('paragosakay-app-qulmw') ||
    host === 'paragosakay-app.ondigitalocean.app'
  ) {
    throw new Error('Refusing to target the known production application');
  }
  if (
    host !== '127.0.0.1' &&
    host !== 'localhost' &&
    !host.includes('staging')
  ) {
    throw new Error('Remote Phase 10 hostname must contain staging');
  }
  return parsed.origin;
};

const positiveInteger = (value, name, maximum) => {
  const parsed = Number(value);
  if (
    !Number.isSafeInteger(parsed) ||
    parsed < 1 ||
    (maximum != null && parsed > maximum)
  ) {
    throw new Error(
      `${name} must be an integer from 1 to ${maximum || 'the safe maximum'}`
    );
  }
  return parsed;
};

const writeSecureJson = (filePath, value) => {
  const resolved = path.resolve(filePath);
  const relative = path.relative(secureDirectory, resolved);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Sensitive output must remain inside .secure-backups');
  }
  fs.mkdirSync(secureDirectory, { recursive: true });
  fs.writeFileSync(resolved, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: 'utf8',
    mode: 0o600,
  });
};

module.exports = {
  loadManifestPath,
  loadStagingBoundary,
  parseMongoTarget,
  positiveInteger,
  readEnvironmentFile,
  rootDir,
  validateStagingBaseUrl,
  writeSecureJson,
};
