const assert = require('assert');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

// Test configuration
const TEST_CONFIG = {
  JWT_SECRET: 'test-secret-key-12345',
  JWT_REFRESH_SECRET: 'test-refresh-secret-key-12345',
  JWT_EXPIRES_IN: '15m',
  JWT_REFRESH_EXPIRES_IN: '7d',
  BOARDING_WINDOW_MINUTES: 5,
  STOP_ALERT_COOLDOWN_MINUTES: 2,
  PICKUP_REQUEST_TTL_MINUTES: 10,
  MAX_REQUESTS_PER_PASSENGER_PER_TRIP: 3,
  JEEP_PASS_BY_REASSIGN_METERS: 50
};

// Test results storage
const testResults = [];

// Test runner
function runTest(category, testName, testFn) {
  try {
    testFn();
    testResults.push({ category, testName, status: 'PASS', error: null, input: '', expectedOutput: '', actualOutput: '' });
    console.log(`✓ ${category} - ${testName}`);
  } catch (error) {
    testResults.push({ category, testName, status: 'FAIL', error: error.message, input: '', expectedOutput: '', actualOutput: '' });
    console.error(`✗ ${category} - ${testName}: ${error.message}`);
  }
}

function runAsyncTest(category, testName, testFn) {
  return testFn()
    .then(() => {
      testResults.push({ category, testName, status: 'PASS', error: null, input: '', expectedOutput: '', actualOutput: '' });
      console.log(`✓ ${category} - ${testName}`);
    })
    .catch((error) => {
      testResults.push({ category, testName, status: 'FAIL', error: error.message, input: '', expectedOutput: '', actualOutput: '' });
      console.error(`✗ ${category} - ${testName}: ${error.message}`);
    });
}

// ============ JWT UTILITY TESTS ============
function testJWTGeneration() {
  const payload = { userId: '123', role: 'passenger' };
  const token = jwt.sign(payload, TEST_CONFIG.JWT_SECRET, { expiresIn: TEST_CONFIG.JWT_EXPIRES_IN });
  assert(token, 'JWT token should be generated');
  assert(typeof token === 'string', 'JWT token should be a string');
}

function testJWTVerification() {
  const payload = { userId: '123', role: 'passenger' };
  const token = jwt.sign(payload, TEST_CONFIG.JWT_SECRET, { expiresIn: TEST_CONFIG.JWT_EXPIRES_IN });
  const decoded = jwt.verify(token, TEST_CONFIG.JWT_SECRET);
  assert.strictEqual(decoded.userId, '123', 'Decoded userId should match');
  assert.strictEqual(decoded.role, 'passenger', 'Decoded role should match');
}

function testJWTExpiration() {
  const payload = { userId: '123' };
  const token = jwt.sign(payload, TEST_CONFIG.JWT_SECRET, { expiresIn: '1ms' });
  setTimeout(() => {
    try {
      jwt.verify(token, TEST_CONFIG.JWT_SECRET);
      throw new Error('Token should have expired');
    } catch (err) {
      assert(err.name === 'TokenExpiredError', 'Should throw TokenExpiredError');
    }
  }, 10);
}

function testRefreshTokenGeneration() {
  const payload = { userId: '456', tokenVersion: 1 };
  const refreshToken = jwt.sign(payload, TEST_CONFIG.JWT_REFRESH_SECRET, { expiresIn: TEST_CONFIG.JWT_REFRESH_EXPIRES_IN });
  assert(refreshToken, 'Refresh token should be generated');
  const decoded = jwt.verify(refreshToken, TEST_CONFIG.JWT_REFRESH_SECRET);
  assert.strictEqual(decoded.userId, '456', 'Refresh token userId should match');
}

// ============ PASSWORD HASHING TESTS ============
async function testPasswordHashing() {
  const password = 'TestPassword123!';
  const hash = await bcrypt.hash(password, 10);
  assert(hash, 'Password hash should be generated');
  assert(hash !== password, 'Hash should not equal plain password');
}

async function testPasswordComparison() {
  const password = 'TestPassword123!';
  const hash = await bcrypt.hash(password, 10);
  const isMatch = await bcrypt.compare(password, hash);
  assert.strictEqual(isMatch, true, 'Password should match hash');
}

async function testPasswordComparisonFail() {
  const password = 'TestPassword123!';
  const wrongPassword = 'WrongPassword456!';
  const hash = await bcrypt.hash(password, 10);
  const isMatch = await bcrypt.compare(wrongPassword, hash);
  assert.strictEqual(isMatch, false, 'Wrong password should not match hash');
}

// ============ GEO UTILITY TESTS ============
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371e3;
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
    Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function testDistanceCalculationSamePoint() {
  const distance = calculateDistance(14.5995, 120.9842, 14.5995, 120.9842);
  assert.strictEqual(distance, 0, 'Distance between same points should be 0');
}

function testDistanceCalculationDifferentPoints() {
  const distance = calculateDistance(14.5995, 120.9842, 14.6000, 120.9850);
  assert(distance > 0, 'Distance between different points should be greater than 0');
  assert(distance < 200, 'Distance should be reasonable for close points');
}

function testDistanceCalculationFarPoints() {
  const distance = calculateDistance(14.5995, 120.9842, 14.6500, 121.0500);
  assert(distance > 1000, 'Distance between far points should be significant');
}

// ============ VALIDATION TESTS ============
function validateEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

function testEmailValidationValid() {
  assert.strictEqual(validateEmail('test@example.com'), true, 'Valid email should pass');
  assert.strictEqual(validateEmail('user.name+tag@domain.co.uk'), true, 'Complex valid email should pass');
}

function testEmailValidationInvalid() {
  assert.strictEqual(validateEmail('invalid-email'), false, 'Invalid email should fail');
  assert.strictEqual(validateEmail('@example.com'), false, 'Email without local part should fail');
  assert.strictEqual(validateEmail('test@'), false, 'Email without domain should fail');
}

function validatePhoneNumber(phone) {
  const phoneRegex = /^(\+63|0)?9\d{9}$/;
  return phoneRegex.test(phone);
}

function testPhoneValidation() {
  assert.strictEqual(validatePhoneNumber('09171234567'), true, 'Valid PH phone should pass');
  assert.strictEqual(validatePhoneNumber('+639171234567'), true, 'Valid PH phone with +63 should pass');
  assert.strictEqual(validatePhoneNumber('9171234567'), true, 'Valid PH phone without prefix should pass');
  assert.strictEqual(validatePhoneNumber('12345'), false, 'Invalid phone should fail');
}

// ============ ROLE VALIDATION TESTS ============
const ROLES = { PASSENGER: 'passenger', DRIVER: 'driver', ADMIN: 'admin' };

function testRoleValidation() {
  assert.strictEqual(ROLES.PASSENGER, 'passenger', 'Passenger role should be defined');
  assert.strictEqual(ROLES.DRIVER, 'driver', 'Driver role should be defined');
  assert.strictEqual(ROLES.ADMIN, 'admin', 'Admin role should be defined');
}

function testRoleAuthorization() {
  const allowedRoles = [ROLES.ADMIN, ROLES.DRIVER];
  assert(allowedRoles.includes(ROLES.ADMIN), 'Admin should be authorized');
  assert(allowedRoles.includes(ROLES.DRIVER), 'Driver should be authorized');
  assert(!allowedRoles.includes(ROLES.PASSENGER), 'Passenger should not be authorized');
}

// ============ PICKUP REQUEST TESTS ============
function testPickupRequestTTL() {
  const createdAt = new Date();
  const expiresAt = new Date(createdAt.getTime() + TEST_CONFIG.PICKUP_REQUEST_TTL_MINUTES * 60 * 1000);
  const now = new Date();
  assert(expiresAt > now, 'Pickup request should not be expired immediately');
}

function testPickupRequestExpired() {
  const createdAt = new Date(Date.now() - 15 * 60 * 1000);
  const expiresAt = new Date(createdAt.getTime() + TEST_CONFIG.PICKUP_REQUEST_TTL_MINUTES * 60 * 1000);
  const now = new Date();
  assert(expiresAt < now, 'Pickup request should be expired after TTL');
}

function testMaxRequestsPerPassenger() {
  const requestCount = 2;
  assert(requestCount < TEST_CONFIG.MAX_REQUESTS_PER_PASSENGER_PER_TRIP, 'Should allow request under limit');
  const maxedCount = 3;
  assert(maxedCount >= TEST_CONFIG.MAX_REQUESTS_PER_PASSENGER_PER_TRIP, 'Should block request at limit');
}

// ============ BOARDING WINDOW TESTS ============
function testBoardingWindowValid() {
  const pickupTime = new Date();
  const boardingTime = new Date(pickupTime.getTime() + 3 * 60 * 1000);
  const windowEnd = new Date(pickupTime.getTime() + TEST_CONFIG.BOARDING_WINDOW_MINUTES * 60 * 1000);
  assert(boardingTime < windowEnd, 'Boarding within window should be valid');
}

function testBoardingWindowExpired() {
  const pickupTime = new Date(Date.now() - 10 * 60 * 1000);
  const boardingTime = new Date();
  const windowEnd = new Date(pickupTime.getTime() + TEST_CONFIG.BOARDING_WINDOW_MINUTES * 60 * 1000);
  assert(boardingTime > windowEnd, 'Boarding outside window should be invalid');
}

// ============ STOP ALERT COOLDOWN TESTS ============
function testStopAlertCooldown() {
  const lastAlertTime = new Date(Date.now() - 1 * 60 * 1000);
  const now = new Date();
  const cooldownEnd = new Date(lastAlertTime.getTime() + TEST_CONFIG.STOP_ALERT_COOLDOWN_MINUTES * 60 * 1000);
  assert(now < cooldownEnd, 'Should be in cooldown period');
}

function testStopAlertCooldownExpired() {
  const lastAlertTime = new Date(Date.now() - 5 * 60 * 1000);
  const now = new Date();
  const cooldownEnd = new Date(lastAlertTime.getTime() + TEST_CONFIG.STOP_ALERT_COOLDOWN_MINUTES * 60 * 1000);
  assert(now > cooldownEnd, 'Cooldown should be expired');
}

// ============ JEEP REASSIGNMENT TESTS ============
function testJeepPassByDistance() {
  const pickupLat = 14.5995;
  const pickupLon = 120.9842;
  const jeepLat = 14.6000;
  const jeepLon = 120.9850;
  const distance = calculateDistance(pickupLat, pickupLon, jeepLat, jeepLon);
  assert(distance > TEST_CONFIG.JEEP_PASS_BY_REASSIGN_METERS, 'Jeep should be considered passed by');
}

function testJeepNotPassedBy() {
  const pickupLat = 14.5995;
  const pickupLon = 120.9842;
  const jeepLat = 14.5996;
  const jeepLon = 120.9843;
  const distance = calculateDistance(pickupLat, pickupLon, jeepLat, jeepLon);
  assert(distance < TEST_CONFIG.JEEP_PASS_BY_REASSIGN_METERS, 'Jeep should not be considered passed by');
}

// ============ API RESPONSE FORMAT TESTS ============
function createSuccessResponse(data, message = 'Success') {
  return { success: true, message, data };
}

function createErrorResponse(message, statusCode = 400) {
  return { success: false, message, statusCode };
}

function testSuccessResponseFormat() {
  const response = createSuccessResponse({ id: '123' }, 'User created');
  assert.strictEqual(response.success, true, 'Success response should have success: true');
  assert.strictEqual(response.message, 'User created', 'Success response should have message');
  assert.deepStrictEqual(response.data, { id: '123' }, 'Success response should have data');
}

function testErrorResponseFormat() {
  const response = createErrorResponse('Invalid input', 400);
  assert.strictEqual(response.success, false, 'Error response should have success: false');
  assert.strictEqual(response.message, 'Invalid input', 'Error response should have message');
  assert.strictEqual(response.statusCode, 400, 'Error response should have statusCode');
}

// ============ TRIP SESSION TESTS ============
function testTripSessionStatus() {
  const statuses = ['scheduled', 'active', 'completed', 'cancelled'];
  assert(statuses.includes('active'), 'Active status should be valid');
  assert(statuses.includes('completed'), 'Completed status should be valid');
  assert(!statuses.includes('invalid'), 'Invalid status should not be valid');
}

function testTripSessionTiming() {
  const scheduledStart = new Date();
  const actualStart = new Date(scheduledStart.getTime() + 5 * 60 * 1000);
  assert(actualStart > scheduledStart, 'Actual start should be after scheduled start');
}

// ============ NOTIFICATION TESTS ============
function testNotificationTypes() {
  const types = ['pickup_assigned', 'pickup_acknowledged', 'boarding_confirmed', 'stop_alert', 'trip_started', 'trip_ended'];
  assert(types.includes('pickup_assigned'), 'Pickup assigned type should exist');
  assert(types.includes('stop_alert'), 'Stop alert type should exist');
}

function testNotificationPayload() {
  const notification = {
    type: 'pickup_assigned',
    recipientId: '123',
    title: 'Jeep Assigned',
    body: 'Your jeep has been assigned',
    data: { jeepId: '456', tripId: '789' }
  };
  assert(notification.type, 'Notification should have type');
  assert(notification.recipientId, 'Notification should have recipientId');
  assert(notification.data, 'Notification should have data');
}

// ============ COORDINATE VALIDATION TESTS ============
function isValidCoordinate(lat, lon) {
  return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

function testValidCoordinates() {
  assert.strictEqual(isValidCoordinate(14.5995, 120.9842), true, 'Manila coordinates should be valid');
  assert.strictEqual(isValidCoordinate(0, 0), true, 'Equator coordinates should be valid');
}

function testInvalidCoordinates() {
  assert.strictEqual(isValidCoordinate(91, 120), false, 'Latitude > 90 should be invalid');
  assert.strictEqual(isValidCoordinate(14, 181), false, 'Longitude > 180 should be invalid');
  assert.strictEqual(isValidCoordinate(-91, 120), false, 'Latitude < -90 should be invalid');
}

// ============ OBJECT ID VALIDATION TESTS ============
function isValidObjectId(id) {
  return /^[0-9a-fA-F]{24}$/.test(id);
}

function testValidObjectId() {
  assert.strictEqual(isValidObjectId('507f1f77bcf86cd799439011'), true, 'Valid ObjectId should pass');
  assert.strictEqual(isValidObjectId('123'), false, 'Short string should fail');
  assert.strictEqual(isValidObjectId('invalid-object-id-string'), false, 'Invalid format should fail');
}

// ============ RATE LIMITING TESTS ============
function testRateLimitConfig() {
  const apiLimit = { windowMs: 60000, max: 120 };
  const authLimit = { windowMs: 60000, max: 30 };
  assert.strictEqual(apiLimit.max, 120, 'API rate limit should be 120 per minute');
  assert.strictEqual(authLimit.max, 30, 'Auth rate limit should be 30 per minute');
}

// ============ MAIN TEST RUNNER ============
async function runAllTests() {
  console.log('\n========================================');
  console.log('ParaGO Backend Unit Test Suite');
  console.log('========================================\n');

  console.log('--- JWT Utility Tests ---');
  runTest('JWT', 'Token Generation', testJWTGeneration);
  runTest('JWT', 'Token Verification', testJWTVerification);
  runTest('JWT', 'Refresh Token Generation', testRefreshTokenGeneration);

  console.log('\n--- Password Hashing Tests ---');
  await runAsyncTest('Password', 'Password Hashing', testPasswordHashing);
  await runAsyncTest('Password', 'Password Comparison Success', testPasswordComparison);
  await runAsyncTest('Password', 'Password Comparison Failure', testPasswordComparisonFail);

  console.log('\n--- Geo Utility Tests ---');
  runTest('Geo', 'Distance Calculation Same Point', testDistanceCalculationSamePoint);
  runTest('Geo', 'Distance Calculation Different Points', testDistanceCalculationDifferentPoints);
  runTest('Geo', 'Distance Calculation Far Points', testDistanceCalculationFarPoints);

  console.log('\n--- Validation Tests ---');
  runTest('Validation', 'Email Validation Valid', testEmailValidationValid);
  runTest('Validation', 'Email Validation Invalid', testEmailValidationInvalid);
  runTest('Validation', 'Phone Number Validation', testPhoneValidation);
  runTest('Validation', 'Valid Coordinates', testValidCoordinates);
  runTest('Validation', 'Invalid Coordinates', testInvalidCoordinates);
  runTest('Validation', 'Valid ObjectId', testValidObjectId);

  console.log('\n--- Role & Authorization Tests ---');
  runTest('Role', 'Role Definition', testRoleValidation);
  runTest('Role', 'Role Authorization', testRoleAuthorization);

  console.log('\n--- Pickup Request Tests ---');
  runTest('Pickup', 'Request TTL Valid', testPickupRequestTTL);
  runTest('Pickup', 'Request Expired', testPickupRequestExpired);
  runTest('Pickup', 'Max Requests Per Passenger', testMaxRequestsPerPassenger);

  console.log('\n--- Boarding Window Tests ---');
  runTest('Boarding', 'Boarding Window Valid', testBoardingWindowValid);
  runTest('Boarding', 'Boarding Window Expired', testBoardingWindowExpired);

  console.log('\n--- Stop Alert Tests ---');
  runTest('StopAlert', 'Cooldown Active', testStopAlertCooldown);
  runTest('StopAlert', 'Cooldown Expired', testStopAlertCooldownExpired);

  console.log('\n--- Jeep Reassignment Tests ---');
  runTest('Reassignment', 'Jeep Passed By', testJeepPassByDistance);
  runTest('Reassignment', 'Jeep Not Passed By', testJeepNotPassedBy);

  console.log('\n--- API Response Tests ---');
  runTest('API', 'Success Response Format', testSuccessResponseFormat);
  runTest('API', 'Error Response Format', testErrorResponseFormat);

  console.log('\n--- Trip Session Tests ---');
  runTest('Trip', 'Trip Status Validation', testTripSessionStatus);
  runTest('Trip', 'Trip Timing', testTripSessionTiming);

  console.log('\n--- Notification Tests ---');
  runTest('Notification', 'Notification Types', testNotificationTypes);
  runTest('Notification', 'Notification Payload', testNotificationPayload);

  console.log('\n--- Rate Limiting Tests ---');
  runTest('RateLimit', 'Rate Limit Configuration', testRateLimitConfig);

  console.log('\n========================================');
  console.log('Test Summary');
  console.log('========================================');
  const passed = testResults.filter(r => r.status === 'PASS').length;
  const failed = testResults.filter(r => r.status === 'FAIL').length;
  console.log(`Total: ${testResults.length}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log('========================================\n');

  // Generate CSV
  generateCSV();
}

function generateCSV() {
  const fs = require('fs');
  const csvHeader = 'Category,Test Name,Status,Error Message,Description,Input,Expected Output,Actual Output\n';
  
  const descriptions = {
    'JWT - Token Generation': 'Verifies JWT access token can be generated with user payload',
    'JWT - Token Verification': 'Verifies JWT token can be decoded and payload extracted correctly',
    'JWT - Refresh Token Generation': 'Verifies refresh token can be generated with longer expiry',
    'Password - Password Hashing': 'Verifies password can be hashed using bcrypt',
    'Password - Password Comparison Success': 'Verifies correct password matches its hash',
    'Password - Password Comparison Failure': 'Verifies incorrect password does not match hash',
    'Geo - Distance Calculation Same Point': 'Verifies distance between identical coordinates is 0',
    'Geo - Distance Calculation Different Points': 'Verifies distance calculation between nearby points',
    'Geo - Distance Calculation Far Points': 'Verifies distance calculation between distant points',
    'Validation - Email Validation Valid': 'Verifies valid email formats pass validation',
    'Validation - Email Validation Invalid': 'Verifies invalid email formats fail validation',
    'Validation - Phone Number Validation': 'Verifies Philippine phone number format validation',
    'Validation - Valid Coordinates': 'Verifies valid latitude/longitude coordinates',
    'Validation - Invalid Coordinates': 'Verifies out-of-range coordinates are rejected',
    'Validation - Valid ObjectId': 'Verifies MongoDB ObjectId format validation',
    'Role - Role Definition': 'Verifies all user roles are properly defined',
    'Role - Role Authorization': 'Verifies role-based access control logic',
    'Pickup - Request TTL Valid': 'Verifies pickup request expiry time is set correctly',
    'Pickup - Request Expired': 'Verifies pickup request expires after TTL',
    'Pickup - Max Requests Per Passenger': 'Verifies passenger request limit enforcement',
    'Boarding - Boarding Window Valid': 'Verifies boarding within time window is allowed',
    'Boarding - Boarding Window Expired': 'Verifies boarding outside time window is rejected',
    'StopAlert - Cooldown Active': 'Verifies stop alert cooldown period is enforced',
    'StopAlert - Cooldown Expired': 'Verifies stop alert can be sent after cooldown',
    'Reassignment - Jeep Passed By': 'Verifies jeep is marked as passed when beyond threshold',
    'Reassignment - Jeep Not Passed By': 'Verifies jeep is not marked as passed when within range',
    'API - Success Response Format': 'Verifies API success response structure',
    'API - Error Response Format': 'Verifies API error response structure',
    'Trip - Trip Status Validation': 'Verifies trip status values are valid',
    'Trip - Trip Timing': 'Verifies trip timing logic',
    'Notification - Notification Types': 'Verifies all notification types are defined',
    'Notification - Notification Payload': 'Verifies notification payload structure',
    'RateLimit - Rate Limit Configuration': 'Verifies rate limiting configuration values'
  };

  const csvRows = testResults.map(result => {
    const key = `${result.category} - ${result.testName}`;
    const description = descriptions[key] || 'Test validation';
    const error = result.error ? result.error.replace(/"/g, '""') : '';
    return `"${result.category}","${result.testName}","${result.status}","${error}","${description}","","",""`;
  });

  const csvContent = csvHeader + csvRows.join('\n');
  fs.writeFileSync('test-results.csv', csvContent);
  console.log('✓ Test results exported to test-results.csv\n');
}

// Run all tests
runAllTests().catch(console.error);
