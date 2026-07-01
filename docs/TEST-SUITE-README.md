# ParaGO Backend Unit Test Suite

## Overview

This suite validates the backend business rules used by the passenger, driver, and admin applications. It is intentionally lightweight and can run without starting the API server.

## Current Coverage

Total tests: 56

- JWT and persistent session token behavior
- Password hashing and comparison
- Geolocation calculations
- Input validation
- Role authorization
- Pickup request lifecycle
- Boarding windows
- Automatic onboard proximity timing
- Automatic offboard separation timing
- Hybrid terminal dispatch rules
- Explicit route terminal settings
- Terminal queue sorting and skipped-status handling
- Stop alert cooldowns
- Automatic reassignment pass-by checks
- Destination approach checks
- API response format
- Trip state rules
- Notification payload rules
- Rate limit configuration

## Running Tests

```bash
npm test
```

The command runs `node test.js`, prints pass/fail output, and regenerates `test-results.csv`.

## Important Auth Tests

The login persistence flow is covered at the backend logic level by:

- `JWT - Token Generation`
- `JWT - Token Verification`
- `JWT - Refresh Token Generation`
- `JWT - Refresh Token Rotation State`

The rotation-state test checks the rule behind 1-time login: refresh tokens are stored as hashes, an old refresh token is revoked when a new one is issued, and the old token links to the replacement hash. This supports app restart/session restore without asking users to log in every time.

## Test Configuration

```javascript
JWT_SECRET: 'test-secret-key-12345'
JWT_REFRESH_SECRET: 'test-refresh-secret-key-12345'
JWT_EXPIRES_IN: '15m'
JWT_REFRESH_EXPIRES_IN: '7d'
BOARDING_WINDOW_MINUTES: 5
AUTO_BOARDING_DWELL_SECONDS: 10
AUTO_OFFBOARDING_DISTANCE_METERS: 120
AUTO_OFFBOARDING_CONSECUTIVE_OUTSIDE_CHECKS: 3
STOP_ALERT_COOLDOWN_MINUTES: 2
PICKUP_REQUEST_TTL_MINUTES: 10
MAX_REQUESTS_PER_PASSENGER_PER_TRIP: 3
JEEP_PASS_BY_REASSIGN_METERS: 50
```

## Output Files

- `test-results.csv`: generated summary for spreadsheet review.
- `test-results-detailed.csv`: existing detailed manual/test documentation artifact.

## Adding Tests

1. Add a test function in `test.js`.
2. Call it from `runAllTests()`.
3. Add a matching description in `generateCSV()`.
4. Run `npm test`.
5. Update this README when coverage changes.

## Related Documentation

- [ONE_TIME_LOGIN.md](ONE_TIME_LOGIN.md)
- [TERMINAL_SETTINGS.md](TERMINAL_SETTINGS.md)
- [TERMINAL_QUEUE_MANAGEMENT.md](TERMINAL_QUEUE_MANAGEMENT.md)
- [AUTOMATIC_ONBOARDING.md](AUTOMATIC_ONBOARDING.md)
- [AUTOMATIC_OFFBOARDING.md](AUTOMATIC_OFFBOARDING.md)
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)
- [AUTOMATIC_REASSIGNMENT.md](AUTOMATIC_REASSIGNMENT.md)
- [PARAGO_System_Instruction_Manual.md](PARAGO_System_Instruction_Manual.md)
