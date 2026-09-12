const { SESv2Client, SendEmailCommand, GetAccountCommand } = require('@aws-sdk/client-sesv2');
const nodemailer = require('nodemailer');
const { awsRegion } = require('../config/env');
const { createAuthEmailService } = require('./authEmailTransport');
const client = new SESv2Client({ region: awsRegion || 'ap-southeast-1' });
module.exports = createAuthEmailService({
  createTransport: (options) => nodemailer.createTransport(options),
  sesSend: (kind, message) => kind === 'account'
    ? client.send(new GetAccountCommand({}))
    : client.send(new SendEmailCommand({
      FromEmailAddress: 'SakayGaray <no-reply@sakaygaray.com>',
      Destination: { ToAddresses: [message.email] },
      Content: { Simple: {
        Subject: { Data: message.subject, Charset: 'UTF-8' },
        Body: { Text: { Data: message.text, Charset: 'UTF-8' } },
      } },
    })),
});
