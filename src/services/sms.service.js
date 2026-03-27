const axios = require('axios');

const { smsApiPhApiKey, smsApiPhBaseUrl } = require('../config/env');
const ApiError = require('../utils/apiError');

const normalizedBaseUrl = String(smsApiPhBaseUrl || '').trim().replace(/\/+$/, '');

const ensureSmsApiConfigured = () => {
  if (!smsApiPhApiKey || !normalizedBaseUrl) {
    throw new ApiError(503, 'SMS delivery is not configured on the server');
  }
};

const sendSms = async ({ recipient, message }) => {
  ensureSmsApiConfigured();

  try {
    const response = await axios.post(
      `${normalizedBaseUrl}/send/sms`,
      {
        recipient,
        message,
      },
      {
        timeout: 15000,
        headers: {
          'x-api-key': smsApiPhApiKey,
          'Content-Type': 'application/json',
        },
      }
    );

    return response.data;
  } catch (error) {
    const messageText =
      error.response?.data?.message ||
      error.response?.data?.error ||
      error.message ||
      'SMS delivery failed';
    throw new ApiError(502, `Unable to send verification code: ${messageText}`);
  }
};

module.exports = {
  sendSms,
  ensureSmsApiConfigured,
};
