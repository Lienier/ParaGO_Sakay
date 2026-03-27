const express = require('express');
const {
  registerEmail,
  loginEmail,
  startAdminLoginOtp,
  verifyAdminLoginOtp,
  socialLogin,
  firebaseGoogleLogin,
  refreshSession,
  logoutSession,
  changePassword,
  requestPasswordReset,
  resetPassword,
  buildProfile,
} = require('../services/auth.service');
const authenticate = require('../middlewares/authenticate');
const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/response');
const ApiError = require('../utils/apiError');

const router = express.Router();
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const isStrongPassword = (password) => String(password || '').trim().length >= 8;

router.post(
  '/register-email',
  asyncHandler(async (req, res) => {
    const { email, password, fullName, role } = req.body || {};
    if (!email || !password || !fullName) {
      throw new ApiError(400, 'email, password, and fullName are required');
    }
    const requestedRole = String(role || 'PASSENGER').toUpperCase();
    if (requestedRole !== 'PASSENGER') {
      throw new ApiError(
        403,
        'Driver and admin accounts must be created by an admin account'
      );
    }
    if (!emailPattern.test(String(email).trim())) {
      throw new ApiError(400, 'Invalid email format');
    }
    if (!isStrongPassword(password)) {
      throw new ApiError(400, 'Password must be at least 8 characters long');
    }
    if (role && !['PASSENGER'].includes(requestedRole)) {
      throw new ApiError(400, 'Invalid role');
    }
    const result = await registerEmail({ email, password, fullName, role: requestedRole });
    return ok(res, result, 'Registration successful', 201);
  })
);

router.post(
  '/login-email',
  asyncHandler(async (req, res) => {
    const { email, password, role } = req.body || {};
    if (!email || !password) throw new ApiError(400, 'email and password required');
    if (!emailPattern.test(String(email).trim())) {
      throw new ApiError(400, 'Invalid email format');
    }
    const requestedRole = String(role || '').trim().toUpperCase();
    if (requestedRole && !['PASSENGER', 'DRIVER', 'ADMIN'].includes(requestedRole)) {
      throw new ApiError(400, 'Invalid role');
    }
    const result = await loginEmail({ email, password, role: requestedRole || undefined });
    return ok(res, result, 'Login successful');
  })
);

router.post(
  '/admin/login/start',
  asyncHandler(async (req, res) => {
    const { email, password, phone } = req.body || {};
    if (!email || !password) {
      throw new ApiError(400, 'email and password required');
    }
    if (!emailPattern.test(String(email).trim())) {
      throw new ApiError(400, 'Invalid email format');
    }

    const result = await startAdminLoginOtp({
      email,
      password,
      phone,
    });
    return ok(res, result, 'Verification code sent');
  })
);

router.post(
  '/admin/login/verify',
  asyncHandler(async (req, res) => {
    const { challengeId, code } = req.body || {};
    const result = await verifyAdminLoginOtp({ challengeId, code });
    return ok(res, result, 'Admin login successful');
  })
);

router.post(
  '/social/:provider',
  asyncHandler(async (req, res) => {
    const { provider } = req.params;
    const { token, role } = req.body || {};
    if (!['google', 'facebook'].includes(provider)) {
      throw new ApiError(400, 'Unsupported provider');
    }
    if (!token) throw new ApiError(400, 'Provider token required');
    if (role && String(role).toUpperCase() !== 'PASSENGER') {
      throw new ApiError(
        403,
        'Driver and admin accounts must be created by an admin account'
      );
    }
    const result = await socialLogin({ provider, token, role });
    return ok(res, result, 'Social login successful');
  })
);

router.post(
  '/firebase/google',
  asyncHandler(async (req, res) => {
    const { idToken, role } = req.body || {};
    if (!idToken) throw new ApiError(400, 'Firebase ID token required');
    if (role && String(role).toUpperCase() !== 'PASSENGER') {
      throw new ApiError(
        403,
        'Driver and admin accounts must be created by an admin account'
      );
    }
    const result = await firebaseGoogleLogin({ idToken, role });
    return ok(res, result, 'Firebase Google login successful');
  })
);

router.post(
  '/forgot-password',
  asyncHandler(async (req, res) => {
    const { email } = req.body || {};
    if (!email || !emailPattern.test(String(email).trim())) {
      throw new ApiError(400, 'Valid email is required');
    }
    const result = await requestPasswordReset({ email });
    return ok(res, result, 'If the account exists, reset instructions were generated');
  })
);

router.post(
  '/reset-password',
  asyncHandler(async (req, res) => {
    const { token, newPassword } = req.body || {};
    if (!token || !isStrongPassword(newPassword)) {
      throw new ApiError(400, 'token and valid newPassword are required');
    }
    await resetPassword({ token, newPassword });
    return ok(res, null, 'Password reset successful');
  })
);

router.post(
  '/refresh',
  asyncHandler(async (req, res) => {
    const { refreshToken } = req.body || {};
    const result = await refreshSession({ refreshToken });
    return ok(res, result, 'Token refreshed');
  })
);

router.get(
  '/me',
  authenticate,
  asyncHandler(async (req, res) => {
    return ok(res, { user: await buildProfile(req.user) }, 'Profile');
  })
);

router.post(
  '/logout',
  asyncHandler(async (_req, res) => {
    const { refreshToken } = _req.body || {};
    if (!refreshToken) throw new ApiError(400, 'refreshToken required');
    await logoutSession({ refreshToken });
    return ok(res, null, 'Logout successful');
  })
);

router.post(
  '/change-password',
  authenticate,
  asyncHandler(async (req, res) => {
    const { currentPassword, newPassword } = req.body || {};
    if (!isStrongPassword(newPassword)) {
      throw new ApiError(400, 'newPassword must be at least 8 characters long');
    }
    await changePassword({
      userId: req.user._id,
      currentPassword,
      newPassword,
    });
    return ok(res, null, 'Password updated successfully');
  })
);

module.exports = router;
