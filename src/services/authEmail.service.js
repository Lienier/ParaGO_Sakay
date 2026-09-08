const { SESv2Client, SendEmailCommand, GetAccountCommand } = require('@aws-sdk/client-sesv2');
const { awsRegion } = require('../config/env');
const ApiError = require('../utils/apiError');
const client = new SESv2Client({ region: awsRegion || 'ap-southeast-1' });
let healthyUntil = 0;
const ensureAuthEmailAvailable = async () => {
  if (process.env.AUTH_EMAIL_ENABLED !== 'true') {
    throw new ApiError(503, 'Email authentication is not available yet');
  }
  if (Date.now() < healthyUntil) return;
  try {
    const account = await client.send(new GetAccountCommand({}));
    if (!account.SendingEnabled || !account.ProductionAccessEnabled) throw new Error('SES not ready');
    healthyUntil = Date.now() + 30000;
  } catch (_) {
    throw new ApiError(503, 'Email authentication is temporarily unavailable');
  }
};
const sendAuthEmail = async ({ email, subject, text }) => {
  await ensureAuthEmailAvailable();
  try {
    await client.send(new SendEmailCommand({
      FromEmailAddress: 'SakayGaray <no-reply@sakaygaray.com>',
      Destination: { ToAddresses: [email] },
      Content: { Simple: {
        Subject: { Data: subject, Charset: 'UTF-8' },
        Body: { Text: { Data: text, Charset: 'UTF-8' } },
      } },
    }));
  } catch (_) {
    healthyUntil = 0;
    throw new ApiError(503, 'Email authentication is temporarily unavailable');
  }
};
module.exports = { sendAuthEmail, ensureAuthEmailAvailable };
