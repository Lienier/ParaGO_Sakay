# ParaGO Backend Unit Test Suite

## Overview
Comprehensive unit test suite for the ParaGO transportation support system backend. Tests all core functionality to ensure the system works correctly and securely.

## Test Coverage

### Total Tests: 33
- ✅ All tests passing
- 🔒 Security-focused validation
- 🎯 Business logic verification
- 📍 Location services testing

## Test Categories

### 1. JWT & Authentication (3 tests)
- Token generation and verification
- Refresh token handling
- Token expiration logic

### 2. Password Security (3 tests)
- Bcrypt hashing
- Password comparison (success/failure)
- Hash integrity

### 3. Geolocation Services (3 tests)
- Distance calculation accuracy
- Same point validation
- Far distance computation

### 4. Input Validation (6 tests)
- Email format validation
- Philippine phone number format
- GPS coordinate validation
- MongoDB ObjectId format

### 5. Role-Based Access Control (2 tests)
- Role definitions (passenger, driver, admin)
- Authorization logic

### 6. Pickup Request Management (3 tests)
- Time-to-live (TTL) validation
- Request expiration
- Per-passenger request limits

### 7. Boarding Process (2 tests)
- Boarding window validation
- Time-based boarding restrictions

### 8. Stop Alert System (2 tests)
- Cooldown period enforcement
- Alert timing validation

### 9. Auto Reassignment (2 tests)
- Jeep pass-by detection
- Distance threshold validation

### 10. API Response Standards (2 tests)
- Success response format
- Error response format

### 11. Trip Management (2 tests)
- Trip status validation
- Trip timing logic

### 12. Notifications (2 tests)
- Notification type definitions
- Payload structure validation

### 13. Security & Rate Limiting (1 test)
- Rate limit configuration

## Running Tests

### Quick Start
```bash
npm test
```

### What Happens
1. Runs all 33 unit tests
2. Displays results in console with ✓/✗ indicators
3. Generates `test-results.csv` with basic results
4. Shows summary: Total/Passed/Failed

### Output Files
- `test-results.csv` - Basic test results
- `test-results-detailed.csv` - Comprehensive test documentation with inputs/outputs

## Test Configuration

Tests use the following configuration values:
```javascript
JWT_SECRET: 'test-secret-key-12345'
JWT_REFRESH_SECRET: 'test-refresh-secret-key-12345'
JWT_EXPIRES_IN: '15m'
JWT_REFRESH_EXPIRES_IN: '7d'
BOARDING_WINDOW_MINUTES: 5
STOP_ALERT_COOLDOWN_MINUTES: 2
PICKUP_REQUEST_TTL_MINUTES: 10
MAX_REQUESTS_PER_PASSENGER_PER_TRIP: 3
JEEP_PASS_BY_REASSIGN_METERS: 50
```

## CSV Files for Excel

### test-results.csv
Basic test results with:
- Category
- Test Name
- Status (PASS/FAIL)
- Error Message (if failed)
- Description

### test-results-detailed.csv
Comprehensive documentation with:
- Category
- Test Name
- Status
- Description
- Input (sample data used)
- Expected Output
- Actual Output
- Test Type (Unit/Integration)
- Priority (Critical/High/Medium)
- Related Feature

## Understanding Test Results

### Console Output
```
✓ Category - Test Name    (PASS)
✗ Category - Test Name    (FAIL with error message)
```

### Summary
```
Total: 33
Passed: 33
Failed: 0
```

## Test Categories Explained

### Critical Tests (Must Pass)
- Password hashing and comparison
- Role definitions and authorization
- Boarding window validation

### High Priority Tests
- JWT token operations
- Geolocation calculations
- Pickup request management
- Auto reassignment logic
- API response formats

### Medium Priority Tests
- Email/phone validation
- Stop alert cooldown
- Notification structure

## Key Features Tested

### 🔐 Security
- JWT token generation and verification
- Password hashing with bcrypt
- Role-based access control
- Rate limiting configuration

### 📍 Location Services
- Haversine distance calculation
- Coordinate validation
- Jeep proximity detection
- Pass-by threshold checking

### 🚌 Core Business Logic
- Pickup request lifecycle
- Boarding time windows
- Stop alert cooldown
- Trip status management
- Auto reassignment rules

### 🔔 Notifications
- Notification types
- Payload structure
- Recipient targeting

### ✅ Data Validation
- Email format (RFC compliant)
- Philippine phone numbers
- MongoDB ObjectIds
- GPS coordinates

## Maintenance

### Adding New Tests
1. Create test function in `test.js`
2. Add to appropriate category section
3. Call in `runAllTests()` function
4. Update descriptions object for CSV export

### Test Structure
```javascript
function testYourFeature() {
  // Arrange: Set up test data
  const input = 'test data';
  
  // Act: Execute the function
  const result = yourFunction(input);
  
  // Assert: Verify the result
  assert.strictEqual(result, expectedValue, 'Error message');
}
```

## Dependencies

Tests use built-in Node.js modules and project dependencies:
- `assert` - Built-in assertion library
- `jsonwebtoken` - JWT operations
- `bcryptjs` - Password hashing
- `fs` - File system (CSV generation)

## Continuous Integration

This test suite is designed to be run:
- Before commits
- In CI/CD pipelines
- Before deployments
- During development

## Troubleshooting

### Tests Fail After Code Changes
1. Review the failing test error message
2. Check if business logic changed
3. Update test expectations if change is intentional
4. Fix code if test reveals a bug

### CSV Not Generated
- Ensure write permissions in ParaGO folder
- Check console for file system errors
- Verify Node.js has fs module access

## Best Practices

✅ Run tests before committing code
✅ Keep tests updated with feature changes
✅ Review CSV files for documentation
✅ Add tests for new features
✅ Maintain 100% pass rate

## Related Documentation

- `README.md` - Main project documentation
- `AUTOMATIC_REASSIGNMENT.md` - Auto reassignment details
- `REALTIME_SUMMARY.md` - Real-time features
- `.env` - Environment configuration

## Support

For issues or questions about tests:
1. Check test error messages in console
2. Review CSV files for test details
3. Verify environment configuration
4. Check that dependencies are installed

---

**Last Updated:** 2024
**Test Suite Version:** 1.0.0
**Total Test Coverage:** 33 unit tests
