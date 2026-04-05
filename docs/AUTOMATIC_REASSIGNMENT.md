# Automatic Jeep Reassignment Feature

## Overview
This feature ensures passengers are always assigned to the nearest available jeepney and automatically reassigns them if the jeep passes by their pickup location.

## How It Works

### 1. Passenger Visibility
- **Endpoint**: `GET /api/v1/trips/active`
- **Access**: All authenticated users (including passengers)
- **Returns**: All active jeepneys across all routes with:
  - Real-time location (`lastKnownLocation`)
  - Jeepney details (plate number, name, capacity)
  - Driver information
  - Route information

### 2. Automatic Assignment
- **Manual trip selection removed**: Passengers can no longer specify `tripSessionId` in pickup requests
- **System auto-assigns**: Always picks the nearest available jeepney based on:
  - Distance from passenger's pickup location
  - Available capacity (seats not occupied or reserved)
  - Driver verification status
  - Jeepney active status
  - Trip accepting requests

### 3. Pass-By Detection & Reassignment

#### Configuration
- `JEEP_PASS_BY_REASSIGN_METERS`: Distance threshold (default: 50 meters)
- If jeep moves more than this distance past the pickup location, request is auto-expired

#### Background Job
- Runs every **15 seconds**
- Checks all pending/acknowledged pickup requests
- Compares jeep's current location with pickup location
- Auto-expires requests where jeep has passed by

#### Workflow
1. **Detection**: Background job detects jeep passed by 50+ meters
2. **Expiration**: Request status changed to `expired`
3. **Passenger Notification**: 
   - Type: `pickup_request_expired`
   - Message: "The assigned jeepney has passed your pickup location. Finding another jeepney for you..."
4. **Driver Notification**:
   - Type: `pickup_request_auto_cancelled`
   - Message: "Pickup request was automatically cancelled as you passed the pickup location."
5. **Passenger Action**: Passenger creates new pickup request
6. **New Assignment**: System assigns next nearest available jeepney

## API Changes

### Modified Endpoints

#### `GET /api/v1/trips/active`
- **Before**: Required DRIVER, ADMIN, PASSENGER roles
- **After**: Open to all authenticated users
- **Purpose**: Let passengers see all active jeeps

#### `GET /api/v1/trips/`
- **Before**: Required DRIVER, ADMIN, PASSENGER roles
- **After**: Required DRIVER, ADMIN only (removed PASSENGER)
- **Purpose**: Passengers don't need historical trip data

#### `POST /api/v1/pickup-requests/`
- **Before**: Accepted optional `tripSessionId` for manual selection
- **After**: Removed manual selection, always auto-assigns
- **Purpose**: Force nearest-jeep assignment

### New Service

#### `src/services/pickupReassignment.service.js`
Functions:
- `hasJeepPassedBy()`: Check if jeep passed pickup location
- `checkAndReassignPassedRequests()`: Background job to expire passed requests

## Environment Variables

```env
# Distance threshold for jeep pass-by detection (meters)
JEEP_PASS_BY_REASSIGN_METERS=50
```

## Notification Types

### New Notifications

1. **`pickup_request_expired`** (to passenger)
   - Sent when jeep passes by pickup location
   - Includes reason: `jeep_passed_by`

2. **`pickup_request_auto_cancelled`** (to driver)
   - Sent when request auto-expires due to pass-by
   - Includes reason: `jeep_passed_by`

## Real-World Scenarios

### Scenario 1: Passenger Misses Jeep
1. Passenger requests pickup at Stop A
2. Jeep #1 (nearest) is assigned
3. Jeep #1 passes by without stopping (non-app user boarded, driver missed notification, etc.)
4. System detects jeep is 50m+ past Stop A
5. Request auto-expires
6. Passenger notified: "Jeepney passed by"
7. Passenger creates new request
8. Jeep #2 (next nearest) is assigned

### Scenario 2: Jeep Full Before Reaching Passenger
1. Passenger requests pickup
2. Jeep assigned
3. Non-app users board and fill capacity
4. Jeep passes by passenger's location
5. Auto-reassignment triggers
6. Next jeep with available capacity is assigned

### Scenario 3: Traffic Delays
1. Passenger sees multiple jeeps on route
2. Nearest jeep assigned but stuck in traffic
3. If jeep doesn't reach passenger and passes by (wrong direction, detour, etc.)
4. System auto-reassigns to next available jeep

## Terminal Queue System (Future Enhancement)

**Question**: Should jeeps at terminal have a queue?

**Answer**: Yes, recommended for future implementation:

### Proposed Logic
- Add `terminalId` and `queuePosition` to TripSession model
- Add `isAtTerminal` boolean flag
- Pickup requests near terminal prioritize by queue position (FIFO)
- Once jeep leaves terminal, switch to distance-based assignment
- Queue automatically updates when jeep departs

### Benefits
- Fair distribution of passengers at terminals
- Prevents all passengers from requesting the same jeep
- Matches real-world jeepney terminal operations
- Reduces driver competition at terminals

## Testing

### Test Cases

1. **Normal Assignment**
   - Create pickup request
   - Verify nearest jeep assigned
   - Verify only that driver receives notification

2. **Pass-By Detection**
   - Create pickup request
   - Update jeep location to 60m past pickup
   - Wait 15 seconds for background job
   - Verify request expired
   - Verify notifications sent

3. **Reassignment**
   - Trigger pass-by scenario
   - Create new pickup request
   - Verify different (next nearest) jeep assigned

4. **Multiple Jeeps Visibility**
   - Start multiple trips on different routes
   - Call `GET /api/v1/trips/active` as passenger
   - Verify all active trips returned

## Performance Considerations

- Background job runs every 15 seconds (configurable)
- Only checks pending/acknowledged requests (not completed/cancelled)
- Uses geospatial calculations (haversine formula)
- Minimal database queries per check
- Can be optimized with geospatial indexes on `lastKnownLocation`

## Future Improvements

1. **Predictive Assignment**: Use jeep direction/speed to predict arrival time
2. **Multi-Jeep Notification**: Notify 2-3 nearest drivers, first to acknowledge wins
3. **Terminal Queue**: Implement FIFO queue for terminal-based assignments
4. **Smart Expiry**: Adjust pass-by threshold based on road type (highway vs local)
5. **Passenger Preferences**: Let passengers set preferences (fastest, most space, etc.)
