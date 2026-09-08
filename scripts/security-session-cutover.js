// Explicit release action. Does not alter account or transportation records.
const connectDb = require('../src/config/db');
const { disconnectDb } = require('../src/config/db');
const RefreshToken = require('../src/models/refreshToken');
const AuthSession = require('../src/models/authSession');
const Challenge = require('../src/models/adminLoginChallenge');
const Reset = require('../src/models/passwordResetToken');
const main = async () => {
  if (!process.argv.includes('--apply')) {
    console.log('Dry run: --apply revokes all sessions, refresh tokens, OTP challenges and reset links.');
    return;
  }
  await connectDb();
  try {
    await AuthSession.createIndexes();
    await RefreshToken.createIndexes();
    await Challenge.createIndexes();
    await Reset.createIndexes();
    const now = new Date();
    await AuthSession.updateMany({ revokedAt: null }, { $set: { revokedAt: now } });
    await RefreshToken.updateMany({ revokedAt: null }, { $set: { revokedAt: now } });
    await Challenge.updateMany({ usedAt: null }, { $set: { usedAt: now } });
    await Reset.updateMany({ usedAt: null }, { $set: { usedAt: now } });
    console.log('Security session cutover complete. Users must sign in again.');
  } finally { await disconnectDb(); }
};
main().catch(() => { console.error('Session cutover failed; inspect secured service logs.'); process.exitCode = 1; });
