const bcrypt = require('bcryptjs');
const axios = require('axios');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const { OAuth2Client } = require('google-auth-library');
const { googleClientIds, facebookAppToken, nodeEnv } = require('../config/env');
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
const { sendSms } = require('./sms.service');

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
  if (value.length < 8) {
    throw new ApiError(400, 'Password must be at least 8 characters long');
  }
};

const normalizeEmail = (email) => String(email || '').trim().toLowerCase();
const normalizeRole = (role) => String(role || '').trim().toUpperCase();
const normalizeAdminPhone = (phone) => {
  const raw = String(phone || '').trim();
  const digits = raw.replace(/\D/g, '');

  if (!digits) {
    return '';
  }
  if (digits.length === 10 && digits.startsWith('9')) {
    return `+63${digits}`;
  }
  if (digits.length === 11 && digits.startsWith('09')) {
    return `+63${digits.slice(1)}`;
  }
  if (digits.length === 12 && digits.startsWith('63')) {
    return `+${digits}`;
  }
  throw new ApiError(400, 'Enter a valid Philippine mobile number');
};
const tryNormalizeAdminPhone = (phone) => {
  try {
    return normalizeAdminPhone(phone);
  } catch (_error) {
    return '';
  }
};
const maskPhone = (phone) => {
  const normalized = normalizeAdminPhone(phone);
  if (normalized.length < 6) {
    return normalized;
  }
  return `${normalized.slice(0, 5)}***${normalized.slice(-2)}`;
};
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

const issueSession = async (user, replacedTokenHash = null) => {
  ensureActiveUser(user);
  // Repair legacy/orphaned accounts created before profile creation became atomic.
  await ensureRoleProfile(user);

  const accessToken = signToken({ sub: user._id.toString(), role: user.role });
  const refreshToken = signToken({ sub: user._id.toString(), role: user.role }, 'refresh');

  const decoded = jwt.decode(refreshToken);
  const expMs = decoded?.exp ? decoded.exp * 1000 : Date.now() + 30 * 24 * 60 * 60 * 1000;
  const newHash = tokenHash(refreshToken);

  await RefreshToken.create({
    userId: user._id,
    tokenHash: newHash,
    expiresAt: new Date(expMs),
  });

  if (replacedTokenHash) {
    await RefreshToken.findOneAndUpdate(
      { tokenHash: replacedTokenHash, revokedAt: null },
      {
        $set: {
          revokedAt: new Date(),
          replacedByHash: newHash,
        },
      }
    );
  }

  return { token: accessToken, refreshToken, user: await buildProfile(user) };
};

const authenticateLocalUser = async ({ email, password, role }) => {
  const requestedRole = ensureAllowedRequestedRole(role);
  const user = await User.findOne({ email: normalizeEmail(email), authProvider: 'local' }).select(
    '+passwordHash'
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
}) => {
  const normalizedEmail = normalizeEmail(email);
  const existing = await User.findOne({ email: normalizedEmail });
  if (existing) throw new ApiError(409, 'Email already registered');

  const normalizedRole = String(role || 'PASSENGER').toUpperCase();
  if (!['PASSENGER', 'DRIVER', 'ADMIN'].includes(normalizedRole)) {
    throw new ApiError(400, 'Invalid role');
  }
  ensureStrongPassword(password);

  const passwordHash = await bcrypt.hash(password, 11);
  const user = await User.create({
    email: normalizedEmail,
    passwordHash,
    fullName,
    phone: phone ? String(phone).trim() : undefined,
    role: normalizedRole,
    authProvider: 'local',
    status,
    isVerified: true,
  });

  if (normalizedRole === 'PASSENGER') {
    await Passenger.create({ userId: user._id });
  } else if (normalizedRole === 'DRIVER') {
    await Driver.create({ userId: user._id });
  } else if (normalizedRole === 'ADMIN') {
    await Admin.create({ userId: user._id });
  }

  return user;
};

const loginEmail = async ({ email, password, role }) => {
  const user = await authenticateLocalUser({ email, password, role });
  return issueSession(user);
};

const startAdminLoginOtp = async ({ email, password, phone }) => {
  const user = await authenticateLocalUser({
    email,
    password,
    role: 'ADMIN',
  });

  const persistedPhone = tryNormalizeAdminPhone(user.phone);
  const requestedPhone = normalizeAdminPhone(phone);
  let targetPhone = persistedPhone;

  if (!targetPhone) {
    if (!requestedPhone) {
      throw new ApiError(
        400,
        'Enter your mobile number to receive the admin verification code'
      );
    }
    targetPhone = requestedPhone;
    user.phone = targetPhone;
    await user.save();
  } else if (requestedPhone && requestedPhone !== targetPhone) {
    throw new ApiError(
      409,
      'This admin account is already linked to a different mobile number'
    );
  }

  const otpCode = generateOtpCode();
  const expiresAt = new Date(Date.now() + ADMIN_OTP_EXPIRY_MS);

  await AdminLoginChallenge.updateMany(
    {
      userId: user._id,
      usedAt: null,
      expiresAt: { $gt: new Date() },
    },
    { $set: { usedAt: new Date() } }
  );

  const challenge = await AdminLoginChallenge.create({
    userId: user._id,
    phone: targetPhone,
    codeHash: tokenHash(otpCode),
    expiresAt,
    maxAttempts: ADMIN_OTP_MAX_ATTEMPTS,
  });

  const responsePayload = {
    challengeId: challenge._id.toString(),
    maskedPhone: maskPhone(targetPhone),
    expiresAt: expiresAt.toISOString(),
    expiresInSeconds: Math.floor(ADMIN_OTP_EXPIRY_MS / 1000),
  };

  await sendSms({
    recipient: targetPhone,
    message: `Your ParaGO admin verification code is ${otpCode}. It expires in 5 minutes.`,
  });

  return responsePayload;
};

const verifyAdminLoginOtp = async ({ challengeId, code }) => {
  const normalizedCode = String(code || '').trim();
  if (!challengeId || !normalizedCode) {
    throw new ApiError(400, 'challengeId and code are required');
  }

  const challenge = await AdminLoginChallenge.findById(challengeId);
  if (!challenge || challenge.usedAt || challenge.expiresAt <= new Date()) {
    throw new ApiError(401, 'Invalid or expired verification code');
  }

  if (challenge.attempts >= challenge.maxAttempts) {
    challenge.usedAt = new Date();
    await challenge.save();
    throw new ApiError(429, 'Too many incorrect verification attempts');
  }

  if (challenge.codeHash !== tokenHash(normalizedCode)) {
    challenge.attempts += 1;
    if (challenge.attempts >= challenge.maxAttempts) {
      challenge.usedAt = new Date();
    }
    await challenge.save();
    throw new ApiError(401, 'Invalid or expired verification code');
  }

  const user = await User.findById(challenge.userId).select('+passwordHash');
  ensureActiveUser(user);
  if (user.role !== 'ADMIN') {
    throw new ApiError(403, 'You are not authorized for this resource');
  }

  challenge.usedAt = new Date();
  await challenge.save();

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
    if (!payload?.sub || !payload?.email) return null;
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

      if (!decoded?.uid || !decoded?.email) {
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
  });
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
      user = existingEmailUser;
      user.authProvider = provider;
      user.providerId = profile.providerId;
      user.fullName = user.fullName || profile.fullName;
      user.isVerified = true;
      await user.save();
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
  if (!refreshToken) throw new ApiError(400, 'refreshToken required');

  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch (_error) {
    throw new ApiError(401, 'Invalid or expired refresh token');
  }

  const hash = tokenHash(refreshToken);
  const stored = await RefreshToken.findOne({
    tokenHash: hash,
    revokedAt: null,
    expiresAt: { $gt: new Date() },
  });
  if (!stored) {
    throw new ApiError(401, 'Refresh token no longer valid');
  }

  const user = await User.findById(payload.sub);
  ensureActiveUser(user);

  return issueSession(user, hash);
};

const logoutSession = async ({ refreshToken }) => {
  if (!refreshToken) throw new ApiError(400, 'refreshToken required');

  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch (_error) {
    throw new ApiError(401, 'Invalid or expired refresh token');
  }

  const hash = tokenHash(refreshToken);
  await RefreshToken.findOneAndUpdate(
    {
      tokenHash: hash,
      userId: payload.sub,
      revokedAt: null,
    },
    { $set: { revokedAt: new Date() } }
  );
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

  await RefreshToken.updateMany(
    { userId: user._id, revokedAt: null },
    { $set: { revokedAt: new Date() } }
  );
};

const requestPasswordReset = async ({ email }) => {
  const normalizedEmail = normalizeEmail(email);
  const user = await User.findOne({ email: normalizedEmail, authProvider: 'local' }).select(
    '_id status'
  );

  // Intentionally return generic success even when user does not exist.
  if (!user || user.status !== 'active') {
    return { delivered: true };
  }

  const rawToken = crypto.randomBytes(32).toString('hex');
  const hash = tokenHash(rawToken);
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000);

  await PasswordResetToken.create({
    userId: user._id,
    tokenHash: hash,
    expiresAt,
  });

  // In thesis/dev mode, expose token so the app can proceed without email SMTP setup.
  if (nodeEnv === 'development') {
    return { delivered: true, resetToken: rawToken, expiresAt };
  }
  return { delivered: true };
};

const resetPassword = async ({ token, newPassword }) => {
  if (!token || !newPassword) {
    throw new ApiError(400, 'token and newPassword are required');
  }
  ensureStrongPassword(newPassword);

  const hash = tokenHash(token);
  const record = await PasswordResetToken.findOne({
    tokenHash: hash,
    usedAt: null,
    expiresAt: { $gt: new Date() },
  });
  if (!record) {
    throw new ApiError(401, 'Invalid or expired reset token');
  }

  const user = await User.findById(record.userId).select('+passwordHash');
  ensureActiveUser(user);
  if (user.authProvider !== 'local') {
    throw new ApiError(400, 'Password reset is only available for email login accounts');
  }

  user.passwordHash = await bcrypt.hash(newPassword, 11);
  await user.save();

  record.usedAt = new Date();
  await record.save();

  await RefreshToken.updateMany(
    { userId: user._id, revokedAt: null },
    { $set: { revokedAt: new Date() } }
  );
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
