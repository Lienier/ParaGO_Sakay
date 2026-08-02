const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const rootDir = path.resolve(__dirname, '..');
const backupDir = path.join(rootDir, '.secure-backups');
const encryptedBackup = path.join(
  backupDir,
  'parago-production-20260729T070023Z.archive.gz.gpg',
);
const manifestPath = `${encryptedBackup}.manifest.json`;
const temporaryArchive = path.join(
  backupDir,
  `.restore-verification-${process.pid}.archive.gz`,
);
const mongoRestore = path.join(
  rootDir,
  '.tools',
  'mongodb-msi',
  'MongoDB',
  'Tools',
  '100',
  'bin',
  'mongorestore.exe',
);
const mongoBinaryCache = path.join(
  os.tmpdir(),
  'parago-mongodb-binaries',
);
const restoreDatabase = 'parago_restore_verification';
const gpgExecutable = [
  path.join(process.env.ProgramFiles || '', 'GnuPG', 'bin', 'gpg.exe'),
  path.join(process.env['ProgramFiles(x86)'] || '', 'GnuPG', 'bin', 'gpg.exe'),
  'gpg.exe',
].find((candidate) => candidate === 'gpg.exe' || fs.existsSync(candidate));

function assertPathInside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Temporary archive resolved outside the secure backup directory.');
  }
}

function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  const file = fs.openSync(filePath, 'r');
  const buffer = Buffer.allocUnsafe(64 * 1024);

  try {
    let bytesRead;
    do {
      bytesRead = fs.readSync(file, buffer, 0, buffer.length, null);
      if (bytesRead > 0) {
        hash.update(buffer.subarray(0, bytesRead));
      }
    } while (bytesRead > 0);
  } finally {
    fs.closeSync(file);
  }

  return hash.digest('hex').toUpperCase();
}

function run(command, args, label) {
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    windowsHide: false,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${label} failed with exit code ${result.status}.`);
  }
}

async function main() {
  assertPathInside(backupDir, temporaryArchive);

  if (!fs.existsSync(encryptedBackup) || !fs.existsSync(manifestPath)) {
    throw new Error('Encrypted backup or manifest is missing.');
  }
  if (!fs.existsSync(mongoRestore)) {
    throw new Error('Verified MongoDB restore tool is missing.');
  }

  const manifestText = fs.readFileSync(manifestPath, 'utf8').replace(/^\uFEFF/, '');
  const manifest = JSON.parse(manifestText);
  const encryptedHash = sha256(encryptedBackup);
  if (encryptedHash !== manifest.encryptedSha256) {
    throw new Error('Encrypted backup SHA-256 does not match its manifest.');
  }

  console.log('Encrypted backup hash verified.');
  const memoryServer = await MongoMemoryServer.create({
    binary: {
      downloadDir: mongoBinaryCache,
      version: '8.0.28',
    },
    instance: {
      dbName: restoreDatabase,
      ip: '127.0.0.1',
    },
  });

  try {
    console.log(
      'A GnuPG passphrase prompt may open. Do not enter the passphrase in chat.',
    );
    run(
      gpgExecutable,
      ['--output', temporaryArchive, '--decrypt', encryptedBackup],
      'Backup decryption',
    );

    const decryptedHash = sha256(temporaryArchive);
    if (decryptedHash !== manifest.sourceSha256) {
      throw new Error('Decrypted archive SHA-256 does not match its manifest.');
    }
    console.log('Decrypted archive hash verified.');

    const uri = memoryServer.getUri();
    if (!uri.startsWith('mongodb://127.0.0.1:')) {
      throw new Error('Restore target is not an isolated localhost MongoDB.');
    }

    run(
      mongoRestore,
      [
        `--uri=${uri}`,
        `--archive=${temporaryArchive}`,
        '--gzip',
        '--nsFrom=parago.*',
        `--nsTo=${restoreDatabase}.*`,
        '--noIndexRestore',
        '--stopOnError',
      ],
      'Local restore',
    );

    await mongoose.connect(uri, { dbName: restoreDatabase });
    const collections = await mongoose.connection.db
      .listCollections({}, { nameOnly: true })
      .toArray();

    let documentCount = 0;
    for (const collection of collections) {
      documentCount += await mongoose.connection.db
        .collection(collection.name)
        .countDocuments();
    }

    if (collections.length === 0 || documentCount === 0) {
      throw new Error('Restore completed without any collections or documents.');
    }

    console.log(`Restore verified: ${collections.length} collections.`);
    console.log(`Restore verified: ${documentCount} total documents.`);
    console.log('Restore target was localhost only; Atlas staging was not used.');
  } finally {
    await mongoose.disconnect().catch(() => {});
    await memoryServer.stop();
  }
}

main()
  .catch((error) => {
    console.error(`Restore verification failed: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(() => {
    assertPathInside(backupDir, temporaryArchive);
    if (fs.existsSync(temporaryArchive)) {
      fs.rmSync(temporaryArchive);
      console.log('Temporary decrypted archive removed.');
    }
  });
