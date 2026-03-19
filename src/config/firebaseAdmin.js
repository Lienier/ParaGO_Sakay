const admin = require('firebase-admin');

const { firebaseProjectId, firebaseClientEmail, firebasePrivateKey } = require('./env');

const isFirebaseAdminConfigured = () =>
  Boolean(firebaseProjectId && firebaseClientEmail && firebasePrivateKey);

const getFirebaseApp = () => {
  if (!isFirebaseAdminConfigured()) {
    return null;
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: firebaseProjectId,
        clientEmail: firebaseClientEmail,
        privateKey: firebasePrivateKey,
      }),
    });
  }

  return admin.app();
};

const getFirebaseAuth = () => {
  const app = getFirebaseApp();
  return app ? admin.auth(app) : null;
};

module.exports = {
  getFirebaseAuth,
  isFirebaseAdminConfigured,
};
