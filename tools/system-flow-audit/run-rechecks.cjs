const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'artifacts/system_flow_audit_2026-10-06');
const env = { ...process.env, NODE_ENV: 'test', DEPLOYMENT_ENV: 'test',
  MONGO_URI: 'mongodb://127.0.0.1:27017/unused_audit_test', JWT_SECRET: 'audit-recheck-access-only', JWT_REFRESH_SECRET: 'audit-recheck-refresh-only',
  REDIS_URL: '', AUTH_EMAIL_ENABLED: 'false', GOOGLE_CLIENT_IDS: '', GOOGLE_APPLICATION_CREDENTIALS: '',
  FIREBASE_PROJECT_ID: '', FIREBASE_CLIENT_EMAIL: '', FIREBASE_PRIVATE_KEY: '', GOOGLE_ROUTES_API_KEY: '', TOMTOM_API_KEY: '',
  MONGOMS_SYSTEM_BINARY: path.join(os.tmpdir(), 'parago-mongodb-binaries/mongod-x64-win32-8.2.6.exe'), MONGOMS_SYSTEM_BINARY_VERSION_CHECK: 'false',
  NODE_OPTIONS: '--require ' + JSON.stringify(path.join(__dirname, 'isolate-env.cjs')) };
(async () => {
  for (const name of ['realtime-capacity.characterization', 'terminal-first-operation.integration']) {
    const log = fs.createWriteStream(path.join(output, 'recheck-' + name + '.log'));
    const child = spawn(process.execPath, ['--test', '--test-reporter=tap', path.join(__dirname, 'recheck-with-holiday.cjs')], {
      cwd: root, windowsHide: true, env: { ...env, AUDIT_TEST_FILE: path.join(root, 'tests', name + '.test.js') } });
    child.stdout.pipe(log); child.stderr.pipe(log);
    const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
    await new Promise(resolve => log.end(resolve)); console.log(JSON.stringify({ name, code }));
    if (code) process.exitCode = 1;
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
