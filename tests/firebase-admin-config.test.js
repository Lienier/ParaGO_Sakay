const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const { generateKeyPairSync } = require('node:crypto');
// Real SDK initialization, fake credentials: no Google network requests.
process.env.FIREBASE_PROJECT_ID = 'phase2-sdk-test';
process.env.FIREBASE_CLIENT_EMAIL = 'test@phase2-sdk-test.iam.gserviceaccount.com';
process.env.FIREBASE_PRIVATE_KEY = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
}).privateKey;
const { getApps, deleteApp } = require('firebase-admin/app');
const config = require('../src/config/firebaseAdmin');
test('installed Firebase Admin SDK initializes auth and messaging and reuses its app', () => {
  assert.equal(config.isFirebaseAdminConfigured(), true);
  const messaging = config.getFirebaseMessaging();
  assert.equal(typeof messaging.send, 'function');
  assert.equal(typeof config.getFirebaseAuth().verifyIdToken, 'function');
  assert.equal(config.getFirebaseMessaging(), messaging);
  assert.equal(getApps().length, 1);
});
after(async () => { await Promise.all(getApps().map(deleteApp)); });
