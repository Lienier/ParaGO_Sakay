const { getApps, initializeApp, cert, getApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');

const { firebaseProjectId, firebaseClientEmail, firebasePrivateKey } = require('./env');

const isFirebaseAdminConfigured = () =>
  Boolean(firebaseProjectId && firebaseClientEmail && firebasePrivateKey);

const getFirebaseApp = () => {
  if (!isFirebaseAdminConfigured()) {
    return null;
  }

  if (!getApps().length) {
    initializeApp({
      credential: cert({
        projectId: firebaseProjectId,
        clientEmail: firebaseClientEmail,
        privateKey: firebasePrivateKey,
      }),
    });
  }

  return getApp();
};

const getFirebaseAuth = () => {
  const app = getFirebaseApp();
  return app ? getAuth(app) : null;
};

module.exports = {
  getFirebaseMessaging: () => {
    const app = getFirebaseApp();
    return app ? getMessaging(app) : null;
  },
  getFirebaseAuth,
  isFirebaseAdminConfigured,
};
