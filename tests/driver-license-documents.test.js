const test = require('node:test');
const assert = require('node:assert/strict');

process.env.MONGO_URI ||= 'mongodb://127.0.0.1:27017/parago-test';
process.env.JWT_SECRET ||= 'driver-license-test-secret';
process.env.DRIVER_DOCUMENTS_BUCKET ||= 'parago-driver-documents-test';

const express = require('express');
const request = require('supertest');
const sharp = require('sharp');
const Driver = require('../src/models/driver');
const {
  licensePairUpload,
} = require('../src/middlewares/driverLicenseUpload');
const {
  deleteLicenseDocument,
  presentLicenseDocuments,
  setS3ClientForTests,
  setSignedUrlForTests,
  uploadLicenseDocument,
} = require('../src/services/driverLicenseDocuments.service');

test('driver document metadata is excluded from ordinary Driver queries', () => {
  const path = Driver.schema.path('licenseDocuments');
  assert.equal(path.options.select, false);
});

test('license uploads are normalized to private JPEG S3 objects', async () => {
  const commands = [];
  setS3ClientForTests({
    send: async (command) => {
      commands.push(command);
      return {};
    },
  });
  const source = await sharp({
    create: {
      width: 80,
      height: 50,
      channels: 3,
      background: '#ffffff',
    },
  })
    .png()
    .toBuffer();

  const document = await uploadLicenseDocument({
    driverId: '507f1f77bcf86cd799439011',
    side: 'front',
    file: { buffer: source },
  });

  assert.match(document.objectKey, /^drivers\/507f1f77bcf86cd799439011\/license\/front-/);
  assert.equal(document.mimeType, 'image/jpeg');
  assert.ok(document.sizeBytes > 0);
  assert.equal(commands.length, 1);
  assert.equal(commands[0].input.ContentType, 'image/jpeg');
  assert.equal(commands[0].input.ServerSideEncryption, 'AES256');
});

test('signed document responses omit private object keys', async () => {
  setSignedUrlForTests(async (_client, command) =>
    `https://signed.example/${command.input.Key}`
  );
  const response = await presentLicenseDocuments({
    front: {
      objectKey: 'drivers/one/license/front.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 100,
      uploadedAt: new Date('2026-09-01T00:00:00Z'),
    },
  });
  assert.match(response.front.url, /^https:\/\/signed\.example\//);
  assert.equal(Object.hasOwn(response.front, 'objectKey'), false);
  assert.equal(response.back, null);
});

test('multipart middleware accepts JPEG/PNG and rejects other file types', async () => {
  const app = express();
  app.post('/pair', licensePairUpload, (req, res) => {
    res.json({ front: req.files.licenseFront.length, back: req.files.licenseBack.length });
  });
  app.use((error, _req, res, _next) => {
    res.status(error.statusCode || 500).json({ message: error.message });
  });

  const accepted = await request(app)
    .post('/pair')
    .attach('licenseFront', Buffer.from('jpeg'), {
      filename: 'front.jpg',
      contentType: 'image/jpeg',
    })
    .attach('licenseBack', Buffer.from('png'), {
      filename: 'back.png',
      contentType: 'image/png',
    });
  assert.equal(accepted.status, 200);

  const rejected = await request(app)
    .post('/pair')
    .attach('licenseFront', Buffer.from('text'), {
      filename: 'front.txt',
      contentType: 'text/plain',
    });
  assert.equal(rejected.status, 400);
  assert.match(rejected.body.message, /JPEG or PNG/);
});

test('old S3 object cleanup uses the stored private key', async () => {
  const commands = [];
  setS3ClientForTests({ send: async (command) => commands.push(command) });
  await deleteLicenseDocument({ objectKey: 'drivers/one/license/old.jpg' });
  assert.equal(commands[0].input.Key, 'drivers/one/license/old.jpg');
});
