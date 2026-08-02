const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const secureDir = path.join(rootDir, '.secure-backups');
const rawPath = path.join(secureDir, '.digitalocean-app-spec.raw.json');
const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const encryptedPath = path.join(
  secureDir,
  `digitalocean-app-spec-${timestamp}.json.gpg`,
);
const verificationPath = path.join(
  secureDir,
  `.digitalocean-app-spec-verification-${process.pid}.json`,
);
const manifestPath = `${encryptedPath}.manifest.json`;
const gpgExecutable = [
  path.join(process.env.ProgramFiles || '', 'GnuPG', 'bin', 'gpg.exe'),
  path.join(process.env['ProgramFiles(x86)'] || '', 'GnuPG', 'bin', 'gpg.exe'),
].find((candidate) => fs.existsSync(candidate));

function assertPathInside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Configuration backup path escaped secure storage.');
  }
}

function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
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

function removePlaintext(filePath) {
  assertPathInside(secureDir, filePath);
  if (fs.existsSync(filePath)) {
    fs.rmSync(filePath);
  }
}

function main() {
  for (const filePath of [
    rawPath,
    encryptedPath,
    verificationPath,
    manifestPath,
  ]) {
    assertPathInside(secureDir, filePath);
  }
  if (!gpgExecutable) {
    throw new Error('GnuPG executable is missing.');
  }
  if (!fs.existsSync(rawPath)) {
    throw new Error('Ignored raw DigitalOcean app spec is missing.');
  }

  const sourceSizeBytes = fs.statSync(rawPath).size;
  const sourceSha256 = sha256(rawPath);

  console.log('A GnuPG passphrase prompt may open. Do not enter the passphrase in chat.');
  run(
    gpgExecutable,
    [
      '--symmetric',
      '--cipher-algo',
      'AES256',
      '--output',
      encryptedPath,
      rawPath,
    ],
    'Configuration encryption',
  );
  run(
    gpgExecutable,
    ['--output', verificationPath, '--decrypt', encryptedPath],
    'Configuration decryption verification',
  );

  const verificationSha256 = sha256(verificationPath);
  if (verificationSha256 !== sourceSha256) {
    throw new Error('Decrypted configuration hash does not match the source.');
  }

  const manifest = {
    createdUtc: new Date().toISOString(),
    encryptedFile: path.basename(encryptedPath),
    encryption: 'GnuPG symmetric AES256.CFB',
    sourceFormat: 'DigitalOcean App Platform JSON specification',
    sourceSizeBytes,
    sourceSha256,
    encryptedSizeBytes: fs.statSync(encryptedPath).size,
    encryptedSha256: sha256(encryptedPath),
    decryptionHashVerified: true,
    plaintextRetained: false,
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, {
    encoding: 'utf8',
    flag: 'wx',
  });

  removePlaintext(verificationPath);
  removePlaintext(rawPath);
  console.log(`Encrypted configuration backup: ${path.basename(encryptedPath)}`);
  console.log('Decryption hash verification passed.');
  console.log('Raw and verification plaintext files removed.');
}

try {
  main();
} catch (error) {
  removePlaintext(verificationPath);
  removePlaintext(rawPath);
  console.error(`Configuration backup encryption failed: ${error.message}`);
  process.exitCode = 1;
}
