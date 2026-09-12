const ApiError = require('../utils/apiError');

// Factory permits isolated transport tests without credentials or real email.
const createAuthEmailService = ({ env = process.env, createTransport, sesSend, now = Date.now }) => {
  let healthyUntil = 0;
  let smtp;
  const provider = () => env.AUTH_EMAIL_PROVIDER || 'ses';
  const transport = () => {
    if (!smtp) {
      const user = (env.SMTP_USER || '').trim();
      const pass = (env.SMTP_APP_PASSWORD || '').replace(/\s/g, '');
      if (!/^[^\s@]+@gmail\.com$/i.test(user) || !/^[a-z]{16}$/i.test(pass)) throw new Error('Invalid SMTP configuration');
      smtp = createTransport({
        host: 'smtp.gmail.com', port: 465, secure: true,
        auth: { user, pass }, tls: { minVersion: 'TLSv1.2', rejectUnauthorized: true },
        connectionTimeout: 10000, greetingTimeout: 10000, socketTimeout: 15000,
        logger: false, debug: false, disableFileAccess: true, disableUrlAccess: true,
      });
    }
    return smtp;
  };
  const unavailable = () => new ApiError(503, 'Email authentication is temporarily unavailable');
  const ensureAuthEmailAvailable = async () => {
    if (env.AUTH_EMAIL_ENABLED !== 'true') throw new ApiError(503, 'Email authentication is not available yet');
    if (now() < healthyUntil) return;
    try {
      if (provider() === 'gmail') await transport().verify();
      else if (provider() === 'ses') {
        const account = await sesSend('account');
        if (!account.SendingEnabled || !account.ProductionAccessEnabled) throw new Error('SES not ready');
      } else throw new Error('Unknown email provider');
      healthyUntil = now() + 30000;
    } catch (_) { healthyUntil = 0; throw unavailable(); }
  };
  const sendAuthEmail = async ({ email, subject, text }) => {
    await ensureAuthEmailAvailable();
    try {
      if (provider() === 'gmail') {
        const result = await transport().sendMail({
          from: { name: 'SakayGaray', address: env.SMTP_USER.trim() },
          to: [{ address: email }], subject, text,
        });
        if (!result.accepted?.length || result.rejected?.length) throw new Error('Recipient rejected');
      } else await sesSend('email', { email, subject, text });
    } catch (_) { healthyUntil = 0; throw unavailable(); }
  };
  return { sendAuthEmail, ensureAuthEmailAvailable };
};
module.exports = { createAuthEmailService };
