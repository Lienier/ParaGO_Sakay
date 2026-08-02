const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');
const dotenv = require('dotenv');
const { parseMongoTarget } = require('./start-staging');
const {
  inspectPhase5Migration,
  applyPhase5Migration,
} = require('../src/migrations/phase5DatabaseMigration');

mongoose.set('autoIndex', false);

const rootDir = path.resolve(__dirname, '..');
const confirmation = 'QUARANTINE_DUPLICATES_AND_CREATE_INDEX';

const sha256File = (filePath) =>
  crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
const sha256Value = (value) =>
  crypto.createHash('sha256').update(value).digest('hex');

const parseArgs = (argv) => {
  const value = (name) =>
    argv.find((item) => item.startsWith(`--${name}=`))?.slice(name.length + 3);
  const environment = value('environment');
  const mode = argv.includes('--apply') ? 'apply' : 'dry-run';
  if (!['production', 'staging'].includes(environment)) {
    throw new Error('Use --environment=production or --environment=staging.');
  }
  return {
    environment,
    mode,
    expectedFingerprint: value('expected-fingerprint'),
    confirmation: value('confirm'),
    backupManifest: value('backup-manifest'),
  };
};

const readEnv = (name) =>
  dotenv.parse(fs.readFileSync(path.join(rootDir, name)));

const validateBackup = (manifestArgument) => {
  if (!manifestArgument) {
    throw new Error('Production apply requires --backup-manifest.');
  }
  const manifestPath = path.resolve(rootDir, manifestArgument);
  const secureBackupDir = path.join(rootDir, '.secure-backups');
  const relative = path.relative(secureBackupDir, manifestPath);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Backup manifest must be inside .secure-backups.');
  }
  const manifest = JSON.parse(
    fs.readFileSync(manifestPath, 'utf8').replace(/^\uFEFF/, '')
  );
  const encryptedPath = path.resolve(
    path.dirname(manifestPath),
    manifest.encryptedFile
  );
  const encryptedRelative = path.relative(secureBackupDir, encryptedPath);
  if (encryptedRelative.startsWith('..') || path.isAbsolute(encryptedRelative)) {
    throw new Error('Encrypted backup must be inside .secure-backups.');
  }
  if (!fs.existsSync(encryptedPath)) {
    throw new Error('Encrypted backup file is missing.');
  }
  if (sha256File(encryptedPath).toUpperCase() !== manifest.encryptedSha256) {
    throw new Error('Encrypted backup hash does not match its manifest.');
  }
  if (
    manifest.decryptionHashVerified !== true ||
    manifest.productionDataIncluded !== true
  ) {
    throw new Error('Backup manifest does not prove a verified production backup.');
  }
  const createdAt = new Date(manifest.createdUtc);
  const ageMs = Date.now() - createdAt.getTime();
  if (!Number.isFinite(ageMs) || ageMs < 0 || ageMs > 24 * 60 * 60 * 1000) {
    throw new Error('Production backup must be less than 24 hours old.');
  }
  return {
    createdUtc: createdAt.toISOString(),
    encryptedSha256: manifest.encryptedSha256,
  };
};

const redactPlan = (inspection) => ({
  migrationId: inspection.migrationId,
  fingerprint: inspection.fingerprint,
  duplicateGroups: inspection.duplicateGroups,
  duplicateRideSessions: inspection.duplicateRideSessions,
  blankProviderIds: inspection.blankProviderIds,
  indexes: inspection.indexes,
  alreadyCompleted: inspection.alreadyCompleted,
  groups: inspection.duplicatePlan.map((group) => ({
    pickupRequestRef: sha256Value(Buffer.from(String(group.pickupRequestId))).slice(0, 12),
    canonicalRideRef: sha256Value(
      Buffer.from(String(group.canonicalRideSessionId))
    ).slice(0, 12),
    duplicateRideRefs: group.duplicateRideSessionIds.map((id) =>
      sha256Value(Buffer.from(String(id))).slice(0, 12)
    ),
  })),
});

const run = async () => {
  const args = parseArgs(process.argv.slice(2));
  const production = readEnv('.env');
  const selected =
    args.environment === 'staging' ? readEnv('.env.staging') : production;
  const uri =
    args.environment === 'staging'
      ? selected.STAGING_MONGO_URI || selected.MONGO_URI
      : selected.MONGO_URI;
  const target = parseMongoTarget(uri, 'Phase 5 migration URI', {
    requireSrv: args.environment === 'staging',
  });
  if (
    (args.environment === 'staging' && target.database !== 'parago_staging') ||
    (args.environment === 'production' && target.database === 'parago_staging')
  ) {
    throw new Error('Migration environment does not match its database.');
  }
  if (
    args.environment === 'staging' &&
    uri === production.MONGO_URI
  ) {
    throw new Error('Staging and production MongoDB URIs must differ.');
  }

  if (args.mode === 'apply') {
    if (args.confirmation !== confirmation) {
      throw new Error(`Apply requires --confirm=${confirmation}.`);
    }
    if (args.environment === 'production') {
      const backup = validateBackup(args.backupManifest);
      console.log(
        JSON.stringify({
          type: 'phase5.backup.verified',
          createdUtc: backup.createdUtc,
          encryptedSha256Prefix: backup.encryptedSha256.slice(0, 12),
        })
      );
    }
  }

  await mongoose.connect(uri, {
    autoIndex: false,
    serverSelectionTimeoutMS: 12000,
  });

  const inspection = await inspectPhase5Migration(mongoose.connection.db);
  console.log(
    JSON.stringify({
      type: 'phase5.migration.plan',
      environment: args.environment,
      mode: args.mode,
      database: target.database,
      ...redactPlan(inspection),
    }, null, 2)
  );
  if (args.mode === 'dry-run') return;

  const result = await applyPhase5Migration({
    connection: mongoose.connection,
    expectedFingerprint: args.expectedFingerprint,
  });
  console.log(
    JSON.stringify({
      type: 'phase5.migration.result',
      environment: args.environment,
      applied: result.applied,
      idempotent: result.idempotent,
      remainingDuplicateGroups: result.after.duplicateGroups,
      indexes: result.after.indexes,
    }, null, 2)
  );
};

run()
  .catch((error) => {
    console.error(`Phase 5 migration failed: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect();
  });
