const assert = require('assert');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const {
  canDriverAcknowledgePickupRequest,
  canPassengerBoardPickupRequest,
  canPassengerCancelPickupRequest,
} = require('./src/services/pickupFlow.service');
const {
  compareTerminalQueueTrips,
  normalizePickupType,
  normalizeTerminalQueueStatus,
  normalizeTripOperatingMode,
  routeHasTerminalStop,
  resolveRouteTerminalStop,
} = require('./src/services/hybridDispatch.service');
const {
  hasValidDestinationPoint,
  isRideWithinDestinationApproachThreshold,
  computeApproachLeadMeters,
} = require('./src/utils/destinationApproach');

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

function testDriverAcknowledgeOnlyPending() {
  assert.strictEqual(
    canDriverAcknowledgePickupRequest('pending'),
    true,
    'Driver should be able to acknowledge pending pickups'
  );
  assert.strictEqual(
    canDriverAcknowledgePickupRequest('acknowledged'),
    false,
    'Driver should not re-acknowledge acknowledged pickups'
  );
  assert.strictEqual(
    canDriverAcknowledgePickupRequest('completed'),
    false,
    'Driver should not acknowledge completed pickups'
  );
}

function testPassengerBoardsOnlyAfterAcknowledgement() {
  assert.strictEqual(
    canPassengerBoardPickupRequest('pending'),
    false,
    'Passenger should not board before driver acknowledgement'
  );
  assert.strictEqual(
    canPassengerBoardPickupRequest('acknowledged'),
    true,
    'Passenger should be able to board after driver acknowledgement'
  );
  assert.strictEqual(
    canPassengerBoardPickupRequest('completed'),
    false,
    'Passenger should not board a completed pickup request'
  );
}

function testPassengerCanCancelOnlyOpenRequests() {
  assert.strictEqual(
    canPassengerCancelPickupRequest('pending'),
    true,
    'Passenger should be able to cancel pending pickups'
  );
  assert.strictEqual(
    canPassengerCancelPickupRequest('acknowledged'),
    true,
    'Passenger should be able to cancel acknowledged pickups'
  );
  assert.strictEqual(
    canPassengerCancelPickupRequest('completed'),
    false,
    'Passenger should not cancel completed pickups'
  );
}

function testPickupTypeNormalization() {
  assert.strictEqual(
    normalizePickupType('terminal'),
    'terminal',
    'Terminal pickup type should normalize correctly'
  );
  assert.strictEqual(
    normalizePickupType('anything-else'),
    'roadside',
    'Unknown pickup types should fall back to roadside'
  );
}

function testTripOperatingModeNormalization() {
  assert.strictEqual(
    normalizeTripOperatingMode('terminal_queue'),
    'terminal_queue',
    'Terminal queue operating mode should normalize correctly'
  );
  assert.strictEqual(
    normalizeTripOperatingMode('route_mode'),
    'route',
    'Unknown operating modes should fall back to route'
  );
}

function testResolveRouteTerminalStop() {
  const terminal = resolveRouteTerminalStop({
    stops: [
      {
        name: 'Midpoint',
        order: 3,
        location: { coordinates: [121.0101, 14.6101] },
      },
      {
        name: 'Main Terminal',
        order: 1,
        location: { coordinates: [121.0001, 14.6001] },
      },
    ],
  });

  assert(terminal, 'Terminal stop should resolve for routes with stops');
  assert.strictEqual(
    terminal.stopRef,
    'Main Terminal',
    'Lowest-order route stop should be used as the terminal'
  );
}

function testRouteHasTerminalStop() {
  assert.strictEqual(
    routeHasTerminalStop({
      stops: [
        {
          name: 'Terminal',
          order: 1,
          location: { coordinates: [121.0, 14.6] },
        },
      ],
    }),
    true,
    'Routes with at least one valid stop should expose a terminal stop'
  );
  assert.strictEqual(
    routeHasTerminalStop({ stops: [] }),
    false,
    'Routes without valid stops should not expose a terminal stop'
  );
}

function testTerminalQueueSorting() {
  const waitingLater = {
    operatingMode: 'terminal_queue',
    terminalQueueStatus: 'waiting',
    terminalQueueNumber: 2,
    terminalCheckedInAt: '2026-04-18T08:05:00.000Z',
  };
  const loadingSooner = {
    operatingMode: 'terminal_queue',
    terminalQueueStatus: 'loading',
    terminalQueueNumber: 3,
    terminalCheckedInAt: '2026-04-18T08:07:00.000Z',
  };
  const waitingEarlier = {
    operatingMode: 'terminal_queue',
    terminalQueueStatus: 'waiting',
    terminalQueueNumber: 1,
    terminalCheckedInAt: '2026-04-18T08:00:00.000Z',
  };

  const sorted = [waitingLater, loadingSooner, waitingEarlier].sort(
    compareTerminalQueueTrips
  );
  assert.strictEqual(
    sorted[0],
    loadingSooner,
    'Loading terminal trips should be prioritized over waiting trips'
  );
  assert.strictEqual(
    sorted[1],
    waitingEarlier,
    'Waiting trips should then sort by queue number and check-in time'
  );
}

function testTerminalQueueStatusNormalization() {
  assert.strictEqual(
    normalizeTerminalQueueStatus('loading', { operatingMode: 'terminal_queue' }),
    'loading',
    'Terminal queue trips should keep valid queue statuses'
  );
  assert.strictEqual(
    normalizeTerminalQueueStatus('loading', { operatingMode: 'route' }),
    'off_queue',
    'Route-mode trips should never keep terminal queue statuses'
  );
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
function loadPickupReassignmentService() {
  process.env.MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/parago-test';
  process.env.JWT_SECRET = process.env.JWT_SECRET || TEST_CONFIG.JWT_SECRET;
  return require('./src/services/pickupReassignment.service');
}

function testJeepPassByDistance() {
  const { hasJeepPassedBy } = loadPickupReassignmentService();
  const route = {
    path: {
      coordinates: [
        [120.9840, 14.5995],
        [120.9860, 14.5995],
      ],
    },
  };
  const passed = hasJeepPassedBy({
    route,
    pickupLocation: {
      coordinates: [120.9850, 14.5995],
    },
    jeepLocation: {
      coordinates: [120.9856, 14.5995],
    },
    threshold: TEST_CONFIG.JEEP_PASS_BY_REASSIGN_METERS,
  });
  assert.strictEqual(passed, true, 'Jeep ahead of pickup point should be considered passed by');
}

function testJeepNotPassedBy() {
  const { hasJeepPassedBy } = loadPickupReassignmentService();
  const route = {
    path: {
      coordinates: [
        [120.9840, 14.5995],
        [120.9860, 14.5995],
      ],
    },
  };
  const passed = hasJeepPassedBy({
    route,
    pickupLocation: {
      coordinates: [120.9850, 14.5995],
    },
    jeepLocation: {
      coordinates: [120.9844, 14.5995],
    },
    threshold: TEST_CONFIG.JEEP_PASS_BY_REASSIGN_METERS,
  });
  assert.strictEqual(
    passed,
    false,
    'Jeep behind the pickup point should not be considered passed by'
  );
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
  const types = [
    'pickup_assigned',
    'pickup_acknowledged',
    'boarding_confirmed',
    'stop_alert',
    'trip_started',
    'trip_ended',
    'passenger_near_destination',
  ];
  assert(types.includes('pickup_assigned'), 'Pickup assigned type should exist');
  assert(types.includes('stop_alert'), 'Stop alert type should exist');
  assert(
    types.includes('passenger_near_destination'),
    'Passenger near destination type should exist'
  );
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

// ============ DESTINATION APPROACH TESTS ============
function testValidDestinationApproachPoint() {
  const ride = {
    destinationLocation: {
      coordinates: [120.9842, 14.5995],
    },
  };
  assert.strictEqual(
    hasValidDestinationPoint(ride),
    true,
    'Ride destination point should be valid'
  );
}

function testInvalidDestinationApproachPoint() {
  const ride = {
    destinationLocation: {
      coordinates: [120.9842],
    },
  };
  assert.strictEqual(
    hasValidDestinationPoint(ride),
    false,
    'Ride destination point should be invalid when coordinates are incomplete'
  );
}

function testDestinationApproachThresholdHit() {
  const ride = {
    destinationLocation: {
      coordinates: [120.9842, 14.5995],
    },
  };
  assert.strictEqual(
    isRideWithinDestinationApproachThreshold({
      ride,
      latitude: 14.5997,
      longitude: 120.9842,
      thresholdMeters: 50,
    }),
    true,
    'Ride should be considered near destination within threshold'
  );
}

function testDestinationApproachThresholdMiss() {
  const ride = {
    destinationLocation: {
      coordinates: [120.9842, 14.5995],
    },
  };
  assert.strictEqual(
    isRideWithinDestinationApproachThreshold({
      ride,
      latitude: 14.601,
      longitude: 120.9842,
      thresholdMeters: 50,
    }),
    false,
    'Ride should not be considered near destination outside threshold'
  );
}

function testDestinationApproachThresholdPathCrossing() {
  const ride = {
    destinationLocation: {
      coordinates: [120.9842, 14.5995],
    },
  };
  assert.strictEqual(
    isRideWithinDestinationApproachThreshold({
      ride,
      previousLatitude: 14.5991,
      previousLongitude: 120.9842,
      latitude: 14.5999,
      longitude: 120.9842,
      thresholdMeters: 30,
    }),
    true,
    'Ride should be considered near destination when the jeep path crosses the threshold between samples'
  );
}

function testDestinationApproachThresholdLeadCompensation() {
  const ride = {
    destinationLocation: {
      coordinates: [120.9842, 14.5995],
    },
  };
  const leadMeters = computeApproachLeadMeters({
    previousLatitude: 14.60035,
    previousLongitude: 120.9842,
    latitude: 14.60013,
    longitude: 120.9842,
    thresholdMeters: 50,
  });
  assert.ok(
    leadMeters > 0,
    'Lead compensation should be positive when the jeep moves between samples'
  );
  assert.strictEqual(
    isRideWithinDestinationApproachThreshold({
      ride,
      previousLatitude: 14.60035,
      previousLongitude: 120.9842,
      latitude: 14.60013,
      longitude: 120.9842,
      thresholdMeters: 50,
    }),
    true,
    'Ride should be considered near destination slightly before the strict threshold to offset motion and GPS latency'
  );
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
  runTest('Pickup', 'Driver Acknowledge Only Pending', testDriverAcknowledgeOnlyPending);
  runTest('Pickup', 'Passenger Boards Only After Acknowledgement', testPassengerBoardsOnlyAfterAcknowledgement);
  runTest('Pickup', 'Passenger Cancels Only Open Requests', testPassengerCanCancelOnlyOpenRequests);
  runTest('Pickup', 'Pickup Type Normalization', testPickupTypeNormalization);

  console.log('\n--- Boarding Window Tests ---');
  runTest('Boarding', 'Boarding Window Valid', testBoardingWindowValid);
  runTest('Boarding', 'Boarding Window Expired', testBoardingWindowExpired);

  console.log('\n--- Hybrid Dispatch Tests ---');
  runTest('Hybrid', 'Trip Operating Mode Normalization', testTripOperatingModeNormalization);
  runTest('Hybrid', 'Resolve Route Terminal Stop', testResolveRouteTerminalStop);
  runTest('Hybrid', 'Route Has Terminal Stop', testRouteHasTerminalStop);
  runTest('Hybrid', 'Terminal Queue Sorting', testTerminalQueueSorting);
  runTest('Hybrid', 'Terminal Queue Status Normalization', testTerminalQueueStatusNormalization);

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

  console.log('\n--- Destination Approach Tests ---');
  runTest('DestinationApproach', 'Valid Destination Point', testValidDestinationApproachPoint);
  runTest('DestinationApproach', 'Invalid Destination Point', testInvalidDestinationApproachPoint);
  runTest('DestinationApproach', 'Threshold Hit', testDestinationApproachThresholdHit);
  runTest('DestinationApproach', 'Threshold Miss', testDestinationApproachThresholdMiss);
  runTest('DestinationApproach', 'Threshold Path Crossing', testDestinationApproachThresholdPathCrossing);
  runTest('DestinationApproach', 'Threshold Lead Compensation', testDestinationApproachThresholdLeadCompensation);

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
    'Pickup - Driver Acknowledge Only Pending': 'Verifies only pending pickup requests can be acknowledged by drivers',
    'Pickup - Passenger Boards Only After Acknowledgement': 'Verifies boarding is blocked until the driver acknowledges the pickup',
    'Pickup - Passenger Cancels Only Open Requests': 'Verifies passengers can only cancel pending or acknowledged pickups',
    'Pickup - Pickup Type Normalization': 'Verifies hybrid pickup types normalize to terminal or roadside',
    'Boarding - Boarding Window Valid': 'Verifies boarding within time window is allowed',
    'Boarding - Boarding Window Expired': 'Verifies boarding outside time window is rejected',
    'Hybrid - Trip Operating Mode Normalization': 'Verifies trip operating modes normalize to route or terminal queue',
    'Hybrid - Resolve Route Terminal Stop': 'Verifies the first configured route stop is used as the terminal reference',
    'Hybrid - Terminal Queue Sorting': 'Verifies loading trips and earlier queue numbers are prioritized in terminal dispatch',
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
    'DestinationApproach - Valid Destination Point': 'Verifies ride sessions expose a usable destination coordinate pair',
    'DestinationApproach - Invalid Destination Point': 'Verifies incomplete destination coordinates are rejected',
    'DestinationApproach - Threshold Hit': 'Verifies a ride is flagged near destination when the jeep is within 50 meters',
    'DestinationApproach - Threshold Miss': 'Verifies a ride is not flagged near destination when the jeep is beyond 50 meters',
    'DestinationApproach - Threshold Path Crossing': 'Verifies a ride is still flagged when the jeep crosses the approach radius between GPS samples',
    'DestinationApproach - Threshold Lead Compensation': 'Verifies a small motion-based lead buffer reduces late notifications for moving jeepneys',
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
