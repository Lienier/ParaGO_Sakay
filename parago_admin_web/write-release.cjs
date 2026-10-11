// Public, non-secret build identification for deployment verification.
const fs = require('node:fs');
const path = require('node:path');
const version = /^version:\s*([^+\s]+)\+(\d+)/m.exec(
  fs.readFileSync(path.join(__dirname, 'pubspec.yaml'), 'utf8'));
if (!version) throw new Error('Admin release version is missing');
fs.writeFileSync(path.join(__dirname, 'build/web/release.json'), JSON.stringify({
  app: 'admin', version: version[1], build: Number(version[2]),
  commit: process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA || null,
}, null, 2));
