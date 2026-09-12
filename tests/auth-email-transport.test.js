const test = require('node:test');
const assert = require('node:assert/strict');
const { createAuthEmailService } = require('../src/services/authEmailTransport');
const settings = () => ({ AUTH_EMAIL_ENABLED: 'true', AUTH_EMAIL_PROVIDER: 'gmail', SMTP_USER: 'sender@gmail.com', SMTP_APP_PASSWORD: 'abcdefghijklmnop' });
test('Gmail uses TLS and one sender; SES is never called', async () => {
  let configuration, message;
  const service = createAuthEmailService({ env: settings(),
    createTransport: (options) => { configuration = options; return {
      verify: async () => true, sendMail: async (value) => { message = value; return { accepted: ['recipient@example.com'] }; },
    }; }, sesSend: () => { throw new Error('Unexpected SES'); },
  });
  await service.sendAuthEmail({ email: 'recipient@example.com', subject: 'test', text: 'test' });
  assert.equal(configuration.secure, true);
  assert.equal(configuration.tls.rejectUnauthorized, true);
  assert.equal(configuration.debug, false);
  assert.equal(configuration.disableFileAccess, true);
  assert.equal(message.from.address, 'sender@gmail.com');
  assert.deepEqual(message.to, [{ address: 'recipient@example.com' }]);
});
test('disabled, unknown provider and missing credentials fail closed', async () => {
  for (const env of [{ ...settings(), AUTH_EMAIL_ENABLED: 'false' }, { ...settings(), AUTH_EMAIL_PROVIDER: 'typo' }, { ...settings(), SMTP_APP_PASSWORD: '' }]) {
    const service = createAuthEmailService({ env, createTransport: () => { throw new Error('Not configured'); } });
    await assert.rejects(service.ensureAuthEmailAvailable(), /Email authentication/);
  }
});
test('SMTP failures are redacted and invalidate readiness cache', async () => {
  let verifies = 0;
  const service = createAuthEmailService({ env: settings(), createTransport: () => ({
    verify: async () => { verifies++; }, sendMail: async () => { throw new Error('SECRET provider diagnostic'); },
  }) });
  for (let n = 0; n < 2; n++) await assert.rejects(service.sendAuthEmail({ email: 'recipient@example.com' }), (error) => !error.message.includes('SECRET') && error.statusCode === 503);
  assert.equal(verifies, 2);
});
test('recipient rejection is a failure, not reported as delivery', async () => {
  const service = createAuthEmailService({ env: settings(), createTransport: () => ({ verify: async () => true, sendMail: async () => ({ accepted: [], rejected: ['recipient@example.com'] }) }) });
  await assert.rejects(service.sendAuthEmail({ email: 'recipient@example.com' }), /temporarily unavailable/);
});
test('SES retains production-access guard', async () => {
  const service = createAuthEmailService({ env: { AUTH_EMAIL_ENABLED: 'true' }, sesSend: async () => ({ SendingEnabled: true, ProductionAccessEnabled: false }) });
  await assert.rejects(service.ensureAuthEmailAvailable(), /temporarily unavailable/);
});
