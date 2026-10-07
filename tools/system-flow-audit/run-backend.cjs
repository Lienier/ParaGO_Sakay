const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'artifacts/system_flow_audit_2026-10-06');
fs.mkdirSync(output, { recursive: true });
const env = { ...process.env, NODE_ENV: 'test', DEPLOYMENT_ENV: 'test',
  MONGO_URI: 'mongodb://127.0.0.1:27017/unused_audit_test',
  JWT_SECRET: crypto.randomBytes(48).toString('hex'), JWT_REFRESH_SECRET: crypto.randomBytes(48).toString('hex'),
  REDIS_URL: '', REDIS_NAMESPACE: 'parago:audit:' + crypto.randomUUID(),
  AUTH_EMAIL_ENABLED: 'false', RUN_API_JOBS: 'false',
  FIREBASE_PROJECT_ID: '', FIREBASE_CLIENT_EMAIL: '', FIREBASE_PRIVATE_KEY: '', GOOGLE_APPLICATION_CREDENTIALS: '',
  GOOGLE_CLIENT_IDS: '', FACEBOOK_APP_TOKEN: '', GOOGLE_ROUTES_API_KEY: '', TOMTOM_API_KEY: '',
  DRIVER_DOCUMENTS_BUCKET: '', AWS_ACCESS_KEY_ID: '', AWS_SECRET_ACCESS_KEY: '', AWS_SESSION_TOKEN: '',
  SMSAPIPH_API_KEY: '', SMTP_HOST: '', SES_FROM_EMAIL: '',
  MONGOMS_SYSTEM_BINARY: path.join(os.tmpdir(), 'parago-mongodb-binaries/mongod-x64-win32-8.2.6.exe'),
  MONGOMS_SYSTEM_BINARY_VERSION_CHECK: 'false' };
const preload = path.join(__dirname, 'isolate-env.cjs');
// Propagate only credential isolation to subprocesses; test-specific env overrides still work.
env.NODE_OPTIONS = '--require ' + JSON.stringify(preload);
async function run(name, args, cwd = root) {
  const log = fs.createWriteStream(path.join(output, name + '.log'));
  const started = Date.now();
  const child = spawn(process.execPath, args, { cwd, env, windowsHide: true });
  child.stdout.pipe(log); child.stderr.pipe(log);
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
  await new Promise(resolve => log.end(resolve));
  const result = { name, code, durationMs: Date.now() - started };
  console.log(JSON.stringify(result));
  return result;
}
(async () => {
  const results = [];
  results.push(await run('legacy-unit', [path.join(root, 'test.js')], output));
  const files = fs.readdirSync(path.join(root, 'tests')).filter(n => n.endsWith('.test.js')).sort().map(n => path.join(root, 'tests', n));
  results.push(await run('backend-tests', ['--test', '--test-concurrency=1', '--test-reporter=tap', ...files]));
  fs.writeFileSync(path.join(output, 'backend-run-summary.json'), JSON.stringify({ node: process.version, mongo: '8.2.6', files: files.length, results }, null, 2));
  process.exitCode = results.some(r => r.code !== 0) ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
