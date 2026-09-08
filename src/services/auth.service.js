const bcrypt = require('bcryptjs');
const axios = require('axios');
const crypto = require('crypto');
const mongoose = require('mongoose');
const { OAuth2Client } = require('google-auth-library');
const { googleClientIds, facebookAppToken } = require('../config/env');
const { getFirebaseAuth, isFirebaseAdminConfigured } = require('../config/firebaseAdmin');

const User = require('../models/user');
const Passenger = require('../models/passenger');
const Driver = require('../models/driver');
const Admin = require('../models/admin');
const AdminLoginChallenge = require('../models/adminLoginChallenge');
const RefreshToken = require('../models/refreshToken');
const PasswordResetToken = require('../models/passwordResetToken');
const { signToken, verifyRefreshToken } = require('../utils/jwt');
const tokenHash = require('../utils/tokenHash');
const ApiError = require('../utils/apiError');
const AuthSession = require('../models/authSession');
const { requireSession, revokeSessions, notifyRevocation } = require('./sessionSecurity.service');
const { sendAuthEmail, ensureAuthEmailAvailable } = require('./authEmail.service');
const { reserveAuthEmail } = require('./securityCounters.service');
const { jwtSecret } = require('../config/env');
const otpHash = (challengeId, code) => crypto.createHmac('sha256', jwtSecret).update(`admin-otp:${challengeId}:${code}`).digest('hex');

const GENERIC_LOGIN_FAILURE_MESSAGE = 'Invalid email/password';
const GENERIC_ROLE_SCOPED_LOGIN_FAILURE_MESSAGE =
  'Invalid email/password';
const GENERIC_PASSENGER_REGISTRATION_FAILURE_MESSAGE =
  'Unable to create passenger account with the provided details';
const ADMIN_OTP_EXPIRY_MS = 5 * 60 * 1000;
const ADMIN_OTP_MAX_ATTEMPTS = 5;

const buildProfile = async (user) => {
  if (!user) return null;
  const profile = {
    _id: user._id?.toString() || null,
    role: user.role,
    fullName: user.fullName,
    email: user.email,
    phone: user.phone || null,
  };
  if (user.role === 'PASSENGER') {
    const passenger = await Passenger.findOne({ userId: user._id });
    return { ...profile, passengerId: passenger?._id || null };
  }
  if (user.role === 'DRIVER') {
    const driver = await Driver.findOne({ userId: user._id });
    return { ...profile, driverId: driver?._id || null };
  }
  const admin = await Admin.findOne({ userId: user._id });
  return { ...profile, adminId: admin?._id || null };
};

const ensureActiveUser = (user) => {
  if (!user) throw new ApiError(404, 'User not found');
  if (user.status !== 'active') {
    throw new ApiError(403, 'User account is not active');
  }
};

const ensureStrongPassword = (password) => {
  const value = String(password || '');
  if (typeof password !== 'string' || value.length < 8 || value.length > 128) {
    throw new ApiError(400, 'Password must be between 8 and 128 characters long');
  }
};

const normalizeEmail = (email) => String(email || '').trim().toLowerCase();
const normalizeRole = (role) => String(role || '').trim().toUpperCase();
const generateOtpCode = () => crypto.randomInt(0, 1000000).toString().padStart(6, '0');

const ensureAllowedRequestedRole = (role) => {
  const normalizedRole = normalizeRole(role);
  if (!normalizedRole) return null;
  if (!['PASSENGER', 'DRIVER', 'ADMIN'].includes(normalizedRole)) {
    throw new ApiError(400, 'Invalid role');
  }
  return normalizedRole;
};

const isPassengerScopedRequest = (role) => normalizeRole(role) === 'PASSENGER';
const isRoleScopedRequest = (role) => Boolean(normalizeRole(role));

const throwRoleScopedLoginFailure = () => {
  throw new ApiError(401, GENERIC_ROLE_SCOPED_LOGIN_FAILURE_MESSAGE);
};

const ensureRoleProfile = async (user) => {
  if (user.role === 'PASSENGER') {
    await Passenger.findOneAndUpdate(
      { userId: user._id },
      { $setOnInsert: { userId: user._id } },
      { upsert: true }
    );
    return;
  }

  if (user.role === 'DRIVER') {
    await Driver.findOneAndUpdate(
      { userId: user._id },
      { $setOnInsert: { userId: user._id } },
      { upsert: true }
    );
    return;
  }

  await Admin.findOneAndUpdate(
    { userId: user._id },
    { $setOnInsert: { userId: user._id } },
    { upsert: true }
  );
};

const issueSession = async (user, existingSession = null, dbSession = null) => {
  ensureActiveUser(user);
  await ensureRoleProfile(user);
  const sid = existingSession?._id || crypto.randomUUID();
  const expiresAt = existingSession?.expiresAt || new Date(Date.now() + 30 * 86400000);
  if (!existingSession) await AuthSession.create([{ _id: sid, userId: user._id, expiresAt, authVersion: user.authVersion || 0 }], { session: dbSession });
  const claims = { sub: String(user._id), role: user.role, sid };
  const token = signToken(claims);
  const refreshToken = signToken({ ...claims, exp: Math.floor(expiresAt.getTime() / 1000) }, 'refresh');
  await RefreshToken.create([{ userId: user._id, sessionId: sid,
    tokenHash: tokenHash(refreshToken), expiresAt }], { session: dbSession });
  return { token, refreshToken, user: await buildProfile(user) };
};

const authenticateLocalUser = async ({ email, password, role }) => {
  const requestedRole = ensureAllowedRequestedRole(role);
  const user = await User.findOne({ email: normalizeEmail(email), authProvider: 'local' }).select(
    '+passwordHash +authVersion'
  );
  if (!user) {
    if (isRoleScopedRequest(requestedRole)) {
      throwRoleScopedLoginFailure();
    }
    throw new ApiError(404, GENERIC_LOGIN_FAILURE_MESSAGE);
  }
  if (requestedRole && user.role !== requestedRole) {
    throwRoleScopedLoginFailure();
  }
  if (isRoleScopedRequest(requestedRole) && user.status !== 'active') {
    throwRoleScopedLoginFailure();
  }
  ensureActiveUser(user);

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    if (isRoleScopedRequest(requestedRole)) {
      throwRoleScopedLoginFailure();
    }
    throw new ApiError(401, GENERIC_LOGIN_FAILURE_MESSAGE);
  }

  user.lastLoginAt = new Date();
  await user.save();
  return user;
};

const registerEmail = async ({ email, password, fullName, role = 'PASSENGER' }) => {
  const normalizedEmail = normalizeEmail(email);
  const normalizedRole = ensureAllowedRequestedRole(role) || 'PASSENGER';
  const existing = await User.findOne({ email: normalizedEmail });
  if (existing) {
    if (normalizedRole === 'PASSENGER') {
      throw new ApiError(400, GENERIC_PASSENGER_REGISTRATION_FAILURE_MESSAGE);
    }
    throw new ApiError(409, 'Email already registered');
  }
  ensureStrongPassword(password);

  const passwordHash = await bcrypt.hash(password, 11);
  const session = await mongoose.startSession();
  let user;
  try {
    await session.withTransaction(async () => {
      [user] = await User.create(
        [
          {
            email: normalizedEmail,
            passwordHash,
            fullName,
            role: normalizedRole,
            authProvider: 'local',
            status: 'active',
          },
        ],
        { session }
      );

      if (normalizedRole === 'PASSENGER') {
        await Passenger.create([{ userId: user._id }], { session });
      } else if (normalizedRole === 'DRIVER') {
        await Driver.create([{ userId: user._id }], { session });
      } else if (normalizedRole === 'ADMIN') {
        await Admin.create([{ userId: user._id }], { session });
      }
    });
  } finally {
    await session.endSession();
  }

  return issueSession(user);
};

const createUserByAdmin = async ({
  email,
  password,
  fullName,
  role = 'PASSENGER',
  status = 'active',
  phone,
  session = null,
}) => {
  const createOptions = session ? { session } : {};
  const normalizedEmail = normalizeEmail(email);
  const existing = await User.findOne({ email: normalizedEmail }).session(session);
  if (existing) throw new ApiError(409, 'Email already registered');

  const normalizedRole = String(role || 'PASSENGER').toUpperCase();
  if (!['PASSENGER', 'DRIVER', 'ADMIN'].includes(normalizedRole)) {
    throw new ApiError(400, 'Invalid role');
  }
  ensureStrongPassword(password);

  const passwordHash = await bcrypt.hash(password, 11);
  const [user] = await User.create([{
    email: normalizedEmail,
    passwordHash,
    fullName,
    phone: phone ? String(phone).trim() : undefined,
    role: normalizedRole,
    authProvider: 'local',
    status,
    isVerified: true,
  }], createOptions);

  if (normalizedRole === 'PASSENGER') {
    await Passenger.create([{ userId: user._id }], createOptions);
  } else if (normalizedRole === 'DRIVER') {
    await Driver.create([{ userId: user._id }], createOptions);
  } else if (normalizedRole === 'ADMIN') {
    await Admin.create([{ userId: user._id }], createOptions);
  }

  return user;
};

const loginEmail = async ({ email, password, role }) => {
  const user = await authenticateLocalUser({ email, password, role });
  if (user.role === 'ADMIN') throw new ApiError(403, 'Admin email verification is required');
  return issueSession(user);
};

const startAdminLoginOtp = async ({ email, password }) => {
  await ensureAuthEmailAvailable();
  const user = await authenticateLocalUser({ email, password, role: 'ADMIN' });
  await reserveAuthEmail(user.email);
  const id = new mongoose.Types.ObjectId();
  const code = generateOtpCode();
  const expiresAt = new Date(Date.now() + ADMIN_OTP_EXPIRY_MS);
  await AdminLoginChallenge.updateMany({ userId: user._id, usedAt: null }, { $set: { usedAt: new Date() } });
  await AdminLoginChallenge.create({ _id: id, userId: user._id, email: user.email,
    codeHash: otpHash(String(id), code), expiresAt, maxAttempts: ADMIN_OTP_MAX_ATTEMPTS });
  try {
    await sendAuthEmail({ email: user.email, subject: 'Your SakayGaray admin sign-in code',
      text: `Your sign-in code is ${code}. It expires in 5 minutes. Do not share this code.` });
  } catch (error) {
    await AdminLoginChallenge.updateOne({ _id: id }, { $set: { usedAt: new Date() } });
    throw error;
  }
  const [local, domain] = user.email.split('@');
  return { challengeId: String(id), maskedEmail: `${local.slice(0, 1)}***@${domain}`,
    expiresAt, expiresInSeconds: 300, resendAfterSeconds: 60 };
};

const verifyAdminLoginOtp = async ({ challengeId, code }) => {
  if (!mongoose.isValidObjectId(challengeId) || !/^\d{6}$/.test(String(code || ''))) {
    throw new ApiError(401, 'Invalid or expired verification code');
  }
  const filter = { _id: challengeId, usedAt: null, expiresAt: { $gt: new Date() }, attempts: { $lt: 5 } };
  const codeHash = otpHash(String(challengeId), String(code));
  const challenge = await AdminLoginChallenge.findOneAndUpdate({ ...filter, codeHash },
    { $set: { usedAt: new Date() } }, { new: true });
  if (!challenge) {
    await AdminLoginChallenge.updateOne({ ...filter, codeHash: { $ne: codeHash } }, { $inc: { attempts: 1 } });
    throw new ApiError(401, 'Invalid or expired verification code');
  }
  const user = await User.findById(challenge.userId).select('+authVersion');
  ensureActiveUser(user);
  if (user.role !== 'ADMIN' || user.email !== challenge.email) throw new ApiError(401, 'Please sign in again');
  return issueSession(user);
};

const verifyGoogleToken = async (idToken) => {
  if (!googleClientIds.length) {
    throw new ApiError(503, 'Google login is not configured on the server');
  }

  try {
    const client = new OAuth2Client();
    const ticket = await client.verifyIdToken({
      idToken,
      audience: googleClientIds,
    });
    const payload = ticket.getPayload();
    if (!payload?.sub || !payload?.email || payload.email_verified !== true) return null;
    return {
      providerId: payload.sub,
      email: payload.email.toLowerCase(),
      fullName: payload.name || payload.email.split('@')[0],
    };
  } catch (_error) {
    return null;
  }
};

const verifyFirebaseGoogleToken = async (idToken) => {
  if (isFirebaseAdminConfigured()) {
    try {
      const auth = getFirebaseAuth();
      const decoded = await auth.verifyIdToken(idToken);

      if (!decoded?.uid || !decoded?.email || decoded.email_verified !== true) {
        throw new ApiError(401, 'Invalid Firebase login token');
      }

      const provider = decoded.firebase?.sign_in_provider;
      if (provider !== 'google.com') {
        throw new ApiError(401, 'Firebase token is not a Google login session');
      }

      return {
        providerId: decoded.uid,
        email: decoded.email.toLowerCase(),
        fullName: decoded.name || decoded.email.split('@')[0],
      };
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
    }
  }

  let googleProfile = null;
  try {
    googleProfile = await verifyGoogleToken(idToken);
  } catch (error) {
    if (error instanceof ApiError && error.statusCode === 503) {
      googleProfile = null;
    } else {
      throw error;
    }
  }
  if (googleProfile) {
    return googleProfile;
  }

  if (!isFirebaseAdminConfigured()) {
    throw new ApiError(503, 'Firebase login is not configured on the server');
  }

  throw new ApiError(401, 'Invalid Firebase login token');
};

const verifyFacebookToken = async (accessToken) => {
  if (!facebookAppToken) {
    throw new ApiError(503, 'Facebook login is currently disabled');
  }
  if (!accessToken) return null;
  const debug = await axios.get(
    'https://graph.facebook.com/debug_token',
    {
      params: {
        input_token: accessToken,
        access_token: facebookAppToken,
      },
    }
  );
  if (!debug?.data?.data?.is_valid) return null;
  const profile = await axios.get(
    'https://graph.facebook.com/me',
    {
      params: {
        access_token: accessToken,
        fields: 'id,name,email',
      },
    }
  );
  const result = profile.data || {};
  if (!result.id || !result.email) return null;
  return {
    providerId: result.id,
    email: result.email.toLowerCase(),
    fullName: result.name || result.email.split('@')[0],
  };
};

const issueSocialAccountSession = async ({ profile, provider, role }) => {
  const normalizedRole = ensureAllowedRequestedRole(role);
  if (normalizedRole && normalizedRole !== 'PASSENGER') {
    throw new ApiError(403, 'Driver and admin accounts must be created by an admin account');
  }

  let user = await User.findOne({
    authProvider: provider,
    providerId: profile.providerId,
  }).select('+authVersion');
  if (user && normalizedRole && user.role !== normalizedRole) {
    if (isRoleScopedRequest(normalizedRole)) {
      throwRoleScopedLoginFailure();
    }
    throw new ApiError(401, GENERIC_LOGIN_FAILURE_MESSAGE);
  }

  if (!user) {
    const existingEmailUser = await User.findOne({ email: profile.email });
    if (existingEmailUser) {
      if (normalizedRole && existingEmailUser.role !== normalizedRole) {
        if (isRoleScopedRequest(normalizedRole)) {
          throwRoleScopedLoginFailure();
        }
        throw new ApiError(401, GENERIC_LOGIN_FAILURE_MESSAGE);
      }
      throw new ApiError(409, 'Please use your existing sign-in method');
    } else {
      user = await User.create({
        email: profile.email,
        fullName: profile.fullName,
        role: normalizedRole || 'PASSENGER',
        authProvider: provider,
        providerId: profile.providerId,
        status: 'active',
        isVerified: true,
      });
    }
  }

  if (user.role !== 'PASSENGER') throw new ApiError(403, 'Use your assigned sign-in method');
  if (isPassengerScopedRequest(normalizedRole) && user.status !== 'active') {
    throwRoleScopedLoginFailure();
  }
  await ensureRoleProfile(user);
  ensureActiveUser(user);
  user.lastLoginAt = new Date();
  await user.save();

  return issueSession(user);
};

const socialLogin = async ({ provider, token, role }) => {
  let profile;
  if (provider === 'google') profile = await verifyGoogleToken(token);
  else if (provider === 'facebook') profile = await verifyFacebookToken(token);
  if (!profile) throw new ApiError(401, 'Invalid social token');
  return issueSocialAccountSession({ profile, provider, role });
};

const firebaseGoogleLogin = async ({ idToken, role }) => {
  const profile = await verifyFirebaseGoogleToken(idToken);
  return issueSocialAccountSession({ profile, provider: 'google', role });
};

const refreshSession = async ({ refreshToken }) => {
  let payload;
  try { payload = verifyRefreshToken(refreshToken); }
  catch (_) { throw new ApiError(401, 'Invalid or expired refresh token'); }
  const session = await mongoose.startSession();
  let result;
  try {
    await session.withTransaction(async () => {
      const { active, user } = await requireSession(payload, session);
      const stored = await RefreshToken.findOneAndUpdate({ tokenHash: tokenHash(refreshToken),
        sessionId: payload.sid, userId: payload.sub, revokedAt: null, expiresAt: { $gt: new Date() } },
        { $set: { revokedAt: new Date() } }, { new: true, session });
      if (!stored) throw new ApiError(401, 'Refresh token no longer valid');
      // Write the parent session to serialize rotation with revocation.
      await AuthSession.updateOne({ _id: active._id, revokedAt: null }, { $set: { updatedAt: new Date() } }, { session });
      result = await issueSession(user, active, session);
      await RefreshToken.updateOne({ _id: stored._id }, { $set: { replacedByHash: tokenHash(result.refreshToken) } }, { session });
    });
  } finally { await session.endSession(); }
  return result;
};

const logoutSession = async ({ refreshToken }) => {
  let payload;
  try { payload = verifyRefreshToken(refreshToken); }
  catch (_) { throw new ApiError(401, 'Invalid or expired refresh token'); }
  await revokeSessions({ userId: payload.sub, sessionId: payload.sid });
};

const changePassword = async ({ userId, currentPassword, newPassword }) => {
  if (!currentPassword || !newPassword) {
    throw new ApiError(400, 'currentPassword and newPassword are required');
  }
  ensureStrongPassword(newPassword);

  const user = await User.findById(userId).select('+passwordHash');
  if (!user) throw new ApiError(404, 'User not found');
  if (user.authProvider !== 'local') {
    throw new ApiError(400, 'Password change is only available for email login accounts');
  }
  ensureActiveUser(user);

  const valid = await bcrypt.compare(currentPassword, user.passwordHash);
  if (!valid) throw new ApiError(401, 'Current password is incorrect');

  user.passwordHash = await bcrypt.hash(newPassword, 11);
  await user.save();

  await revokeSessions({ userId: user._id });
};

const requestPasswordReset = async ({ email }) => {
  await ensureAuthEmailAvailable();
  const normalizedEmail = normalizeEmail(email);
  const user = await User.findOne({ email: normalizedEmail, authProvider: 'local', status: 'active' });
  await reserveAuthEmail(normalizedEmail, { send: Boolean(user) });
  if (!user) return { delivered: true };
  const rawToken = crypto.randomBytes(32).toString('hex');
  const record = await PasswordResetToken.create({ userId: user._id, tokenHash: tokenHash(rawToken),
    expiresAt: new Date(Date.now() + 30 * 60000) });
  try {
    await sendAuthEmail({ email: user.email, subject: 'Reset your SakayGaray password',
      text: `Open https://api.sakaygaray.com/reset-password#${rawToken} to reset your password. This link expires in 30 minutes. If you did not request it, ignore this email.` });
  } catch (error) {
    await PasswordResetToken.updateOne({ _id: record._id }, { $set: { usedAt: new Date() } });
    throw error;
  }
  return { delivered: true };
};

const resetPassword = async ({ token, newPassword }) => {
  if (!/^[a-f0-9]{64}$/.test(String(token || ''))) throw new ApiError(401, 'Invalid or expired reset token');
  ensureStrongPassword(newPassword);
  const passwordHash = await bcrypt.hash(newPassword, 11);
  const session = await mongoose.startSession();
  let userId;
  try {
    await session.withTransaction(async () => {
      const record = await PasswordResetToken.findOneAndUpdate({ tokenHash: tokenHash(token), usedAt: null,
        expiresAt: { $gt: new Date() } }, { $set: { usedAt: new Date() } }, { new: true, session });
      if (!record) throw new ApiError(401, 'Invalid or expired reset token');
      userId = record.userId;
      const updated = await User.updateOne({ _id: userId, status: 'active', authProvider: 'local' },
        { $set: { passwordHash } }, { session });
      if (!updated.matchedCount) throw new ApiError(401, 'Invalid reset request');
      await PasswordResetToken.updateMany({ userId, usedAt: null }, { $set: { usedAt: new Date() } }, { session });
      await revokeSessions({ userId, mongoSession: session });
    });
  } finally { await session.endSession(); }
  await notifyRevocation({ userId });
};

module.exports = {
  registerEmail,
  loginEmail,
  startAdminLoginOtp,
  verifyAdminLoginOtp,
  socialLogin,
  firebaseGoogleLogin,
  refreshSession,
  logoutSession,
  changePassword,
  createUserByAdmin,
  requestPasswordReset,
  resetPassword,
  buildProfile,
};
