const crypto = require('crypto');
const sharp = require('sharp');
const {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { awsRegion, driverDocumentsBucket } = require('../config/env');
const ApiError = require('../utils/apiError');

const SIGNED_URL_TTL_SECONDS = 300;
let s3Client;
let signObjectUrl = getSignedUrl;

const getS3Client = () => {
  if (!s3Client) s3Client = new S3Client({ region: awsRegion });
  return s3Client;
};

const requireBucket = () => {
  if (!driverDocumentsBucket) {
    throw new ApiError(503, 'Driver document storage is not configured');
  }
  return driverDocumentsBucket;
};

const normalizeImage = async (buffer) =>
  sharp(buffer)
    .rotate()
    .resize({ width: 2400, height: 2400, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 88, mozjpeg: true })
    .toBuffer();

const uploadLicenseDocument = async ({ driverId, side, file }) => {
  if (!file?.buffer) throw new ApiError(400, `Driver license ${side} image is required`);
  const bucket = requireBucket();
  let body;
  try {
    body = await normalizeImage(file.buffer);
  } catch (_) {
    throw new ApiError(400, `Driver license ${side} image could not be read. Choose a valid JPEG or PNG image`);
  }
  const objectKey = `drivers/${driverId}/license/${side}-${crypto.randomUUID()}.jpg`;
  await getS3Client().send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: objectKey,
      Body: body,
      ContentType: 'image/jpeg',
      ServerSideEncryption: 'AES256',
    })
  ).catch(() => {
    throw new ApiError(503, 'Driver document storage is unavailable. Please try again later');
  });
  return {
    objectKey,
    mimeType: 'image/jpeg',
    sizeBytes: body.length,
    uploadedAt: new Date(),
  };
};

const deleteLicenseDocument = async (document) => {
  if (!document?.objectKey || !driverDocumentsBucket) return;
  await getS3Client().send(
    new DeleteObjectCommand({ Bucket: driverDocumentsBucket, Key: document.objectKey })
  );
};

const presentLicenseDocuments = async (documents) => {
  const result = {};
  for (const side of ['front', 'back']) {
    const document = documents?.[side];
    if (!document?.objectKey) {
      result[side] = null;
      continue;
    }
    const url = await signObjectUrl(
      getS3Client(),
      new GetObjectCommand({ Bucket: requireBucket(), Key: document.objectKey }),
      { expiresIn: SIGNED_URL_TTL_SECONDS }
    );
    result[side] = {
      url,
      mimeType: document.mimeType,
      sizeBytes: document.sizeBytes,
      uploadedAt: document.uploadedAt,
      expiresInSeconds: SIGNED_URL_TTL_SECONDS,
    };
  }
  return result;
};

const setS3ClientForTests = (client) => {
  s3Client = client;
};

const setSignedUrlForTests = (signer) => {
  signObjectUrl = signer;
};

module.exports = {
  deleteLicenseDocument,
  presentLicenseDocuments,
  setS3ClientForTests,
  setSignedUrlForTests,
  uploadLicenseDocument,
};
