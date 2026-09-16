// Invoked by the authenticated PC-only super-admin helper. Never expose as HTTP.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const mongoose = require('mongoose');
const { S3Client, PutObjectCommand, HeadObjectCommand } = require('@aws-sdk/client-s3');
const Release = require('../../src/models/mobileRelease');
const Policy = require('../../src/models/mobileReleasePolicy');
const Audit = mongoose.model('MobileReleaseAudit', new mongoose.Schema({
  app: String, action: String, build: Number, reason: String,
  actor: String, before: mongoose.Schema.Types.Mixed, after: mongoose.Schema.Types.Mixed,
}, { timestamps: true }));
const packages = { driver: 'com.example.parago_mobile', passenger: 'com.parago.passenger' };
// Preserve update compatibility with the already distributed APKs.
const signer = 'b15a75868ae95b63cad8257e2a71fda9c37a882de66ac34ffc8c62746c39a3bc';
function inspectApk(file, app) {
  if (!packages[app] || !path.isAbsolute(file) || !file.toLowerCase().endsWith('.apk')) throw new Error('Release: select a valid APK and application');
  const sdk = process.env.ANDROID_HOME || path.join(process.env.LOCALAPPDATA || '', 'Android/Sdk');
  const versions = fs.readdirSync(path.join(sdk, 'build-tools')).filter(v => /^\d+\.\d+\.\d+$/.test(v))
    .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  if (!versions.length) throw new Error('Release: Android build tools are required');
  const tools = path.join(sdk, 'build-tools', versions[0]);
  const options = { encoding: 'utf8', windowsHide: true, timeout: 60000, maxBuffer: 1024 * 1024 };
  const badging = execFileSync(path.join(tools, 'aapt.exe'), ['dump', 'badging', file], options);
  const metadata = /package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'/.exec(badging);
  if (!metadata || metadata[1] !== packages[app]) throw new Error('Release: APK belongs to the wrong application');
  const build = Number(metadata[2]);
  if (!Number.isSafeInteger(build) || build < 1 || build > 2100000000 || !metadata[3]) throw new Error('Release: invalid APK version');
  if (/application-debuggable/.test(badging)) throw new Error('Release: use a release APK, not a debuggable build');
  const java = process.env.JAVA_HOME ? path.join(process.env.JAVA_HOME, 'bin/java.exe') :
    path.join(process.env.ProgramFiles || 'C:/Program Files', 'Android/Android Studio/jbr/bin/java.exe');
  const signed = execFileSync(java, ['-jar', path.join(tools, 'lib/apksigner.jar'), 'verify', '--verbose', '--print-certs', file], options);
  const certificates = [...signed.matchAll(/Signer #\d+ certificate SHA-256 digest: ([a-f\d]+)/gi)];
  if (certificates.length !== 1 || certificates[0][1].toLowerCase() !== signer) throw new Error('Release: signing certificate does not match existing installations');
  if (!/Verified using v2 scheme.*: true/.test(signed)) throw new Error('Release: APK v2 signature verification failed');
  if (!['arm64-v8a', 'armeabi-v7a', 'x86_64'].every(abi => badging.includes(`'${abi}'`))) throw new Error('Release: choose the universal APK for distribution');
  return { app, packageName: metadata[1], build, version: metadata[3], certificate: signer };
}
function configFromFile(file) {
  const config = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(config.bucket || '') || config.origin !== 'https://downloads.sakaygaray.com') {
    throw new Error('Release: configure the dedicated download bucket and HTTPS domain first');
  }
  return config;
}
async function initialize() {
  await Promise.all([Release.createCollection(), Policy.createCollection(), Audit.createCollection()]);
  await Release.createIndexes();
}
async function upload({ file, app, notes = '' }, config, client = new S3Client({ region: config.region || 'ap-southeast-1' }), inspector = inspectApk) {
  if (typeof notes !== 'string' || notes.length > 2000) throw new Error('Release: notes must be at most 2000 characters');
  if (fs.statSync(file).size > 250 * 1024 * 1024) throw new Error('Release: APK exceeds 250 MB');
  // Inspect an immutable private copy; edits to the selected file cannot change
  // the bytes after validation. The temporary copy is removed in finally.
  const temp = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'sakay-release-'));
  const snapshot = path.join(temp, 'candidate.apk');
  try {
    fs.copyFileSync(file, snapshot, fs.constants.COPYFILE_EXCL);
    const info = inspector(snapshot, app);
    if (await Release.exists({ app, build: { $gte: info.build } })) throw new Error('Release: build number must be newer than all uploaded releases');
    const data = fs.readFileSync(snapshot);
    const digest = crypto.createHash('sha256').update(data).digest();
    const sha256 = digest.toString('hex');
    const objectKey = `releases/${app}/${info.build}/${sha256}.apk`;
    try {
      await client.send(new PutObjectCommand({ Bucket: config.bucket, Key: objectKey, Body: data, IfNoneMatch: '*',
        ContentType: 'application/vnd.android.package-archive', ContentDisposition: `attachment; filename="SakayGaray-${app}-${info.build}.apk"`,
        CacheControl: 'public,max-age=31536000,immutable', ChecksumSHA256: digest.toString('base64') }));
    } catch (error) {
      // A previous attempt may have uploaded successfully before its response
      // was lost. Reuse only an identical, verified object; never overwrite it.
      if (error.name !== 'PreconditionFailed' && error.$metadata?.httpStatusCode !== 412) throw error;
    }
    const stored = await client.send(new HeadObjectCommand({ Bucket: config.bucket, Key: objectKey, ChecksumMode: 'ENABLED' }));
    if (stored.ContentLength !== data.length || stored.ChecksumSHA256 !== digest.toString('base64')) throw new Error('Release: upload verification failed; current release unchanged');
    const record = { ...info, sha256, size: data.length, objectKey, url: `${config.origin}/${objectKey}`, notes };
    const session = await mongoose.startSession();
    try { await session.withTransaction(async () => {
      await Release.create([record], { session });
      await Audit.create([{ app, action: 'upload', build: info.build, actor: 'local-superadmin', reason: notes }], { session });
    }); } finally { await session.endSession(); }
    return { success: true, message: 'APK verified and uploaded as a draft. Check its download before publishing.' };
  } finally { if (fs.existsSync(snapshot)) fs.unlinkSync(snapshot); fs.rmdirSync(temp); }
}
async function changePolicy(input, verifyDownload = async url => {
  const response = await fetch(url, { method: 'HEAD', redirect: 'error', signal: AbortSignal.timeout(15000) });
  return response.ok && response.headers.get('content-length');
}) {
  const { app, operation, build, revision, reason } = input;
  if (!packages[app] || !['publish', 'require', 'optional'].includes(operation) || !Number.isSafeInteger(revision) || revision < 0 ||
    typeof reason !== 'string' || !reason.trim() || reason.length > 500) throw new Error('Release: select a release, reload current policy and provide a reason (1-500 characters)');
  let release;
  if (operation !== 'optional') {
    if (!Number.isSafeInteger(build) || build < 1) throw new Error('Release: invalid build');
    if (operation === 'require' && build < 10) throw new Error('Release: build 10 is the first version with update support; older releases must remain optional');
    release = await Release.findOne({ app, build }).lean();
    if (!release || !release.url.startsWith('https://downloads.sakaygaray.com/releases/')) throw new Error('Release: upload a valid release first');
    if (Number(await verifyDownload(release.url)) !== release.size) throw new Error('Release: public download is unavailable or has an unexpected size');
    if (operation === 'require' && !release.publishedAt) throw new Error('Release: publish and test the APK before requiring it');
  }
  const session = await mongoose.startSession();
  try { await session.withTransaction(async () => {
    const old = await Policy.findById(app).session(session).lean();
    if ((old?.revision || 0) !== revision) throw new Error('Release: policy changed; reload before trying again');
    const next = { latestBuild: old?.latestBuild || 0, minimumBuild: old?.minimumBuild || 0, message: old?.message || '' };
    if (operation === 'publish') {
      if (build <= next.latestBuild) throw new Error('Release: select a newer build for publication');
      next.latestBuild = build;
      await Release.updateOne({ app, build }, { $set: { publishedAt: new Date() } }, { session });
    } else {
      if (operation === 'require' && build > next.latestBuild) throw new Error('Release: required build must already be published');
      next.minimumBuild = operation === 'require' ? build : 0;
      next.message = reason.trim();
    }
    await Policy.updateOne({ _id: app }, { $set: next, $inc: { revision: 1 } }, { session, upsert: true });
    await Audit.create([{ app, action: operation, build, actor: 'local-superadmin', reason, before: old, after: next }], { session });
  }); } finally { await session.endSession(); }
  return { success: true, message: operation === 'publish' ? 'Release published. Required-update policy unchanged.' : 'Update policy saved. Existing sessions and journeys are preserved.' };
}
async function list() {
  return { success: true, message: 'Mobile releases loaded.', releases: await Release.find().sort({ createdAt: -1 }).limit(100).lean(),
    policies: await Policy.find().lean(), history: await Audit.find().sort({ createdAt: -1 }).limit(20).lean() };
}
module.exports = { inspectApk, configFromFile, initialize, upload, changePolicy, list, Audit };
