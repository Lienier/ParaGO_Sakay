# ParaGO Complete System Instruction Manual

Prepared from the current repository state on 2026-04-19

## 1. Document Purpose

This manual explains the whole ParaGO system in one place so a group member can understand:

- what the system is
- which applications are included
- how users move through the system
- what conditions must be satisfied before each process is allowed
- what backend services, validations, and realtime features are active
- how to run, maintain, and review the system

This manual is based on the actual source code in this repository and the current supporting documents in the `docs/` folder.

## 2. System Overview

ParaGO is a transport support system for jeepney-style operations. It is built as one shared backend plus three separate client applications:

- Admin web application
- Driver mobile application
- Passenger mobile application

The system supports the full operational cycle:

1. Admin configures routes, stops, fare settings, drivers, and jeepneys.
2. Driver signs in, becomes available, creates or starts a trip, and shares vehicle location.
3. Passenger selects a route, pins pickup and unload points, and submits a booking request.
4. Backend assigns the nearest eligible active jeepney on the route.
5. Driver acknowledges the pickup request.
6. Passenger validates boarding and becomes onboard.
7. Passenger may send a digital stop alert near the destination.
8. Driver or passenger completes the ride session.
9. Admin monitors operations and reports.

## 3. System Objectives

The current codebase is designed to provide:

- route-aware booking and pickup validation
- driver verification and assignment control
- live trip and jeepney monitoring
- realtime and notification-assisted operations
- onboarding, boarding, ride-session, and unloading support
- admin reporting and route management
- optional terminal queue dispatch in addition to normal route-mode dispatch

## 4. Repository Structure

The repository is organized as follows:

- `src/`
  - Node.js + Express backend
- `parago_admin_web/`
  - Flutter web admin console
- `parago_mobile/`
  - Flutter mobile driver app
- `parago_passenger/`
  - Flutter mobile passenger app
- `docs/`
  - architecture notes, realtime notes, flow diagrams, and related documentation
- `route_payloads/`
  - route payload references and generated route data
- `scripts/`
  - utility scripts used by the project

## 5. Main Technology Stack

### Backend

- Node.js
- Express
- MongoDB Atlas through Mongoose
- JWT access and refresh token authentication
- Socket.IO for optional realtime delivery
- Firebase Admin verification for Google sign-in support
- SMS-based support for admin OTP login

### Client Applications

- Flutter
- Provider for session/state orchestration
- Shared `ApiClient`, `SessionController`, and `TokenStorage` patterns
- Firebase initialization where supported
- Flutter Map for map rendering
- Geolocator for device location features

## 6. High-Level Architecture

### Shared architecture

All three clients connect to the same backend and database. The backend is the source of truth for:

- users
- roles
- routes
- jeepneys
- trip sessions
- pickup requests
- ride sessions
- stop alerts
- notifications
- reports

### Backend startup sequence

The backend starts through:

- `src/server.js`
- `src/app.js`

Important backend startup behavior:

- loads environment variables
- configures security middleware through `helmet`
- configures CORS
- configures request logging through `morgan`
- applies API rate limiting
- mounts route groups under `/api/v1`
- also mounts compatibility routes without `/api/v1`
- exposes health endpoints

### Client startup sequence

All Flutter apps follow the same general startup pattern:

1. `AppConfig.load()`
2. `AppConfig.resolveApiBaseUrl()`
3. Firebase initialization if available
4. create `ApiClient`
5. create `TokenStorage`
6. create `SessionController`
7. restore saved session
8. if authenticated, open the role-specific home screen

## 7. Applications and Responsibilities

### 7.1 Admin Web Application

Location: `parago_admin_web/`

Main responsibilities:

- admin login
- dashboard monitoring
- driver creation and maintenance
- jeepney assignment
- route building
- route management
- landmark editing
- fare setting management
- report viewing
- recent activity review
- hybrid dispatch board review

Main workspace sections currently visible in code:

- Overview
- Drivers
- Route Builder
- Routes
- Fare Settings

### 7.2 Driver Mobile Application

Location: `parago_mobile/`

Main responsibilities:

- driver authentication
- automatic online/offline synchronization
- trip creation and trip startup
- trip ending
- request availability toggling
- pickup request monitoring
- stop alert monitoring
- route and trip map display
- realtime or polling-based update intake
- automatic location sharing

Driver tabs visible in code:

- Drive
- Requests
- Alerts
- Analytics

### 7.3 Passenger Mobile Application

Location: `parago_passenger/`

Main responsibilities:

- passenger authentication and registration
- route browsing
- pickup point selection
- unload point selection
- booking submission
- ride tracking
- onboard tracking
- stop alert sending
- ride completion support
- notification review
- passenger profile management

## 8. User Roles

The backend supports three roles:

- `PASSENGER`
- `DRIVER`
- `ADMIN`

### Role rules

- Passenger accounts may self-register.
- Driver accounts must be created by an admin.
- Admin accounts must be created by an admin or already exist in backend setup.
- Role-based authorization is enforced on protected endpoints.

## 9. Core Data Entities

### User

Shared identity record for all roles.

Important fields:

- email
- passwordHash
- fullName
- phone
- role
- authProvider
- status
- isVerified
- lastLoginAt

### Passenger

Passenger profile extension.

Important fields:

- userId
- phone
- photoUrl
- emergencyContact
- defaultRouteId

### Driver

Driver profile extension.

Important fields:

- userId
- licenseNumber
- employeeNumber
- phone
- assignedJeepneyId
- assignedRouteId
- isVerified
- status
- operatingMode
- terminalQueueStatus

### Admin

Admin profile extension linked to the shared user record.

### Jeepney

Vehicle record used for live operations.

Important fields:

- plateNumber
- capacity
- vehicleTag
- jeepneyName
- manufacturer
- capacityBand
- status
- currentDriverId
- lastKnownLocation
- lastSeenAt

### Route

Operational route definition used across all applications.

Important fields:

- name
- code
- direction
- status
- description
- path
- waypoints
- stops
- navigation
- fareConfig

### TripSession

Live or scheduled operational trip for a jeepney on a route.

Important fields:

- jeepneyId
- driverId
- routeId
- routePathSnapshot
- status
- startedAt
- endedAt
- acceptRequests
- occupancyCount
- active
- operatingMode
- terminalQueueStatus
- terminalQueueNumber

### PickupRequest

Passenger booking request for pickup.

Important fields:

- passengerId
- tripSessionId
- routeId
- pickupType
- stopRef
- pickupLocation
- destinationStopRef
- destinationLocation
- fareSnapshot
- status
- acknowledgedBy
- acknowledgedAt
- expiresAt

### RideSession

Verified onboard ride record.

Important fields:

- passengerId
- tripSessionId
- pickupRequestId
- destinationStopRef
- destinationLocation
- fareSnapshot
- status
- boardedAt
- endedAt
- canSendStopAlert

### StopAlert

Digital unload request.

Important fields:

- passengerId
- tripSessionId
- rideSessionId
- routeId
- stopRef
- note
- location
- status
- acknowledgedBy
- acknowledgedAt

### Notification

Stored in-app notification and realtime event source.

### ActivityLog

Admin-side recent activity log.

## 10. Authentication and Session Process

### Supported authentication flows

- Passenger self-registration by email/password
- Email/password login for passenger, driver, and admin
- Backend admin OTP flow:
  - `/auth/admin/login/start`
  - `/auth/admin/login/verify`
- Firebase Google login
- Social login:
  - Google
  - Facebook
- Refresh token rotation
- Password reset
- Password change

### Authentication conditions

- Email must be valid.
- Password must be at least 8 characters.
- Passenger self-registration only allows `PASSENGER`.
- Driver and admin accounts cannot self-register through the public registration route.
- User status must be `active`.
- Role-scoped login must match the stored role.

### Session process

On successful login:

1. Backend validates credentials.
2. Backend issues an access token.
3. Backend issues a refresh token.
4. Refresh token is stored server-side with revocation and replacement tracking.
5. Client stores tokens locally.
6. Client restores the session through `/auth/me`.
7. If access token expires, client attempts `/auth/refresh`.

## 11. Admin Setup Process

This is the normal system setup order for a new deployment or test cycle.

### Step 1. Create or confirm admin access

Conditions:

- admin user must exist
- admin user must be active
- if OTP flow is used, admin phone must be valid for SMS delivery

### Step 2. Create drivers

Admin can create a driver through `/admin/drivers`.

Required information:

- email
- password
- fullName
- jeepney payload

Optional but operationally important information:

- assignedRouteId
- phone
- licenseNumber
- employeeNumber
- status
- isVerified
- operatingMode

Conditions:

- email must be unique
- jeepney plate number must be unique
- assigned route must exist and be active
- terminal queue mode requires an active route with a terminal stop

### Step 3. Create or manage routes

Admin route builder and route management screens support:

- route creation
- route update
- route deactivation
- landmark editing
- fare setting updates
- route preview generation

Conditions:

- route name and code are required
- path must contain at least two points when provided
- stop ordering must be valid integers
- navigation and fare settings must use valid numeric values

### Step 4. Create or assign jeepneys

Admin can:

- create jeepneys
- update jeepneys
- deactivate jeepneys
- assign jeepneys to drivers

Conditions:

- jeepney must exist
- jeepney must be active before assignment
- jeepney cannot already be assigned to another driver

### Step 5. Review dashboard and dispatch board

Admin dashboard shows:

- active trips
- pending requests
- onboard rides
- active alerts
- terminal queue trips
- route-mode trips
- terminal requests

Hybrid dispatch board shows:

- terminal queue trips
- waiting terminal passengers
- active route-mode drivers

## 12. Route Creation and Maintenance Process

### Route builder process

1. Admin opens Route Builder.
2. Admin sets start pin.
3. Admin sets end pin.
4. Admin may add branch guide points.
5. Backend route preview is requested through Google Routes API, with TomTom as a fallback when needed.
6. Route geometry, distance, and ETA are returned.
7. Admin saves route payload.
8. Admin manages route landmarks and fare settings.

### Route update effects

When a route is updated:

- the route document is updated
- active and scheduled trips using that route receive an updated `routePathSnapshot`

### Route deactivation

Route deletion is soft-delete style:

- route is marked `inactive`
- route is not hard-deleted

## 13. Trip Lifecycle Process

### Trip creation

Trip endpoints:

- `POST /trips`
- `PATCH /trips/:id/start`
- `PATCH /trips/:id/end`
- `PATCH /trips/:id/availability`

### Trip creation conditions

- jeepneyId is required
- routeId is required
- jeepney must exist
- jeepney must be active
- route must exist
- route must be active
- if driver creates the trip:
  - driver account must be active
  - driver must be verified
  - assigned jeepney restrictions are enforced
- if operating mode is `terminal_queue`:
  - route must have a terminal stop

### Trip start conditions

- trip must not already be active
- trip must not already be completed or cancelled
- if driver starts the trip:
  - driver must be active
  - driver must be verified
  - jeepney assignment must match
  - driver must be the assigned driver for the trip or become assigned during start

### Trip start effects

- status becomes `active`
- `startedAt` is set
- `active` becomes true
- `acceptRequests` becomes true
- route path snapshot is ensured
- terminal queue fields are initialized when needed

### Trip end conditions

- trip must not already be closed
- if driver ends the trip, driver must own the trip

### Trip end effects

- status becomes `completed`
- `endedAt` is set
- `active` becomes false
- `acceptRequests` becomes false
- terminal queue status becomes `departed` if applicable

## 14. Operating Modes

The current backend supports two main operating modes for trips and drivers.

### Route mode

Used for normal roadside pickup operations.

Characteristics:

- passenger roadside pickup allowed
- normal route traversal
- driver accepts route-based pickup requests

### Terminal queue mode

Used when a route has a terminal stop and a queue sequence is required.

Characteristics:

- passenger terminal pickup requests are supported
- queue number is assigned
- queue status can be:
  - waiting
  - loading
  - departed
- ordering is based on queue number and check-in time

## 15. Driver Availability and Location Sharing Process

### Driver online/offline logic

The driver app automatically manages online/offline status based on:

- authentication state
- app lifecycle state
- internet connectivity

Important behavior from current implementation:

- signed-in, foreground, connected driver stays online
- background logic tries to keep driver operational when tracking is available
- if app session ends or app becomes detached, driver is treated as offline
- if internet is unavailable, availability is downgraded

### Driver location sharing process

1. Driver is signed in and operational.
2. Location tracking service starts.
3. Device GPS updates are received.
4. Driver app calls `/drivers/me/location`.
5. Backend updates `Jeepney.lastKnownLocation` and `lastSeenAt`.
6. Backend finds the active trip for that jeepney.
7. Backend emits `jeepney.location.updated` through Socket.IO.
8. Passenger clients subscribed to the route or trip receive the update.

### Driver tracking conditions

- valid driver session
- valid latitude and longitude
- driver must resolve to an assigned jeepney or active trip jeepney
- jeepney record must exist

### Driver-side map behavior

Current driver map implementation includes:

- animated vehicle motion
- heading-aware rotation
- overlap-based motion smoothing
- calmer follow camera
- map-ready guard before controller movement

## 16. Passenger Route Browsing and Selection Process

### Passenger route browsing

Passenger can:

- load active routes
- choose a route
- view live route map
- set pickup and unload points
- view live jeepneys on the selected route

### Current selected-route display behavior

The current passenger route-browsing implementation shows:

- only the 3 nearest eligible jeepneys on the selected route
- jeepneys are sorted nearest to the passenger anchor
- jeepneys already more than 100 meters past the anchor along route progress are hidden

Anchor precedence:

- draft pickup point
- current passenger location
- selected route center

Important exception:

- if the passenger is already onboard, the onboarded jeep remains available for ride tracking even if it is outside the route-browsing shortlist

## 17. Pickup Request Process

### Pickup request submission

Endpoint:

- `POST /pickup-requests`

Passenger request flow:

1. Passenger selects route.
2. Passenger sets pickup point.
3. Passenger sets unload point.
4. App sends route, pickup, current location, and destination data.
5. Backend validates request.
6. Backend auto-selects the nearest eligible active jeepney.
7. Pickup request is created with expiry time.
8. Driver is notified.

### Pickup request required information

- routeId
- currentLocation
- pickupLocation or terminal-based pickup context
- destinationLocation
- destinationStopRef

### Pickup request conditions

- route must exist
- route must be active
- currentLocation is required
- pickup point must be within 50 meters of passenger current location
- roadside pickup point must be near the route
- unload point must be within 5 meters of the route
- unload point must come after the pickup point along route progress
- destinationStopRef is required
- passenger cannot exceed the allowed count of open requests for the same trip

### Auto-assignment logic

The backend does not require manual trip choice for booking.

It chooses the best eligible trip by checking:

- active trips on the selected route
- `acceptRequests = true`
- driver exists, active, and verified
- jeepney exists and is active
- enough remaining capacity
- operating mode compatibility:
  - terminal pickup uses terminal queue trips
  - roadside pickup uses route-mode trips

Selection behavior:

- terminal pickup sorts by queue order
- roadside pickup sorts by nearest jeepney distance to the pickup point
- seat availability is used as a tiebreaker

### Pickup request state values

- pending
- acknowledged
- completed
- expired
- cancelled

## 18. Pickup Request Acknowledgment Process

Endpoint:

- `PATCH /pickup-requests/:id/acknowledge`

Flow:

1. Driver opens pickup request queue.
2. Driver chooses a request.
3. Backend checks request status and trip state.
4. Backend verifies driver ownership and readiness.
5. Request becomes `acknowledged`.
6. Passenger receives notification.

### Acknowledgment conditions

- request must exist
- request must still be `pending`
- trip must be active
- driver must be assigned to the trip
- driver must be active
- driver must be verified
- trip jeepney must match the driver's assigned jeepney

## 19. Pickup Request Cancellation and Expiry

### Passenger cancellation

Endpoint:

- `PATCH /pickup-requests/:id/cancel`

Conditions:

- passenger must own the request
- request must be `pending` or `acknowledged`

### Automatic expiry by TTL

Pickup requests are time-limited.

Important configuration:

- `PICKUP_REQUEST_TTL_MINUTES`
- default code value: 12 minutes

### Automatic expiry when jeep passes the pickup point

The backend periodically checks open requests and expires them when:

- assigned jeep is ahead of the pickup point on route progress
- the jeep is more than `JEEP_PASS_BY_REASSIGN_METERS` beyond that pickup

Current default:

- 50 meters

Effects:

- request becomes `expired`
- passenger is notified
- driver is notified
- passenger must create a new request for reassignment

## 20. Boarding Validation Process

Endpoint:

- `POST /boarding/validate`

Flow:

1. Passenger submits tripSessionId and pickupRequestId.
2. Backend loads the request.
3. Backend confirms request ownership and status.
4. Backend confirms trip is active.
5. Backend checks request expiry.
6. Backend checks boarding time window.
7. Backend checks passenger boarding location against pickup reference.
8. Backend confirms destination information exists.
9. Ride session is created as onboard.
10. Pickup request becomes completed.
11. Trip occupancy count is incremented.
12. Driver is notified that passenger boarded.

### Boarding conditions

- pickup request must exist
- request must belong to the passenger
- request must match the trip
- request must already be acknowledged
- request must not be expired
- trip must be active
- boarding must occur within the allowed time window
- passenger must be near the pickup area
- no existing active ride session for the same passenger and trip
- destination stop and coordinates must be valid

### Boarding distance and time controls

Current code-based rules:

- boarding window default: 10 minutes
- boarding location grace distance: 250 meters from pickup area

## 21. Ride Session Process

### Ride states

- waiting
- onboard
- completed

### Ride creation

Created by the boarding validation flow.

### Ride completion

Endpoint:

- `PATCH /ride-sessions/:id/complete`

Who can complete:

- passenger
- driver
- admin

Conditions:

- ride must exist
- ride must be `onboard`
- passenger can only complete their own ride
- driver can only complete rides on their own trip

Effects:

- status becomes `completed`
- `endedAt` is set
- `canSendStopAlert` becomes false
- trip occupancy count is decremented
- active stop alerts tied to that ride are dismissed
- passenger receives ride completion notification

## 22. Stop Alert Process

Endpoint:

- `POST /stop-alerts`

Flow:

1. Passenger is onboard.
2. Passenger selects stop alert target.
3. App sends tripSessionId, stopRef, optional note, and location.
4. Backend verifies ride, trip, and route state.
5. Alert is created with status `sent`.
6. Driver receives notification.

### Stop alert conditions

- passenger must have an onboard ride session for the trip
- ride must allow stop alerts
- trip must be active
- route must exist
- alert location must be on or near the route
- stop alert cooldown must be respected

### Stop alert cooldown

Current default:

- 2 minutes

### Stop alert location tolerance

Current unload-road tolerance:

- 5 meters

### Stop alert acknowledgment

Endpoint:

- `PATCH /stop-alerts/:id/acknowledge`

Conditions:

- alert must exist
- trip must exist
- if caller is driver, driver must own the trip

Effects:

- alert becomes `acknowledged`
- passenger receives notification

## 23. Notifications and Realtime Process

### Notification publication model

Most important operational actions create notifications. Current examples include:

- pickup request created
- pickup request acknowledged
- pickup request cancelled
- pickup request expired
- passenger boarded
- stop alert created
- stop alert acknowledged
- ride completed

### Realtime model

Socket.IO is optional but implemented.

Socket features include:

- user rooms
- role rooms
- route rooms
- trip rooms

Important events:

- `notification.created`
- `ops.changed`
- `jeepney.location.updated`

### Passenger realtime ownership model

Current passenger live location behavior:

- websocket route/trip updates are the preferred live source
- API refresh is fallback when realtime becomes stale or disconnected
- trip markers are animated independently per trip

### Driver realtime behavior

Current driver behavior:

- driver publishes location to backend
- backend broadcasts active-trip location events
- driver app also uses realtime or polling for request and stop alert updates

### Admin realtime behavior

Current admin behavior:

- admin listens to `ops.changed` when realtime is enabled
- otherwise admin dashboard polls every 30 seconds

## 24. Reporting and Monitoring Process

Admin report endpoints:

- `/reports/requests`
- `/reports/boarding`
- `/reports/alerts`
- `/reports/trip-activity`
- `/reports/route-demand`
- `/reports/passenger-flow`

### Current report coverage

- pickup requests by status
- ride sessions by status
- stop alerts by status
- trip sessions by status
- route demand volume
- passenger boarding and unloading flow over time
- top boarding and unload locations

## 25. Important Validation Rules Summary

### Driver rules

- driver account must be active for operational actions
- driver must be verified for trip creation, trip start, and pickup handling
- assigned jeepney restrictions are enforced

### Route rules

- route must exist
- route must be active for operational use
- terminal queue mode requires a route terminal stop

### Jeepney rules

- jeepney must exist
- jeepney must be active for operations
- one jeepney cannot be actively assigned to multiple drivers

### Passenger booking rules

- pickup must stay near passenger current location
- pickup must be near the route
- unload must be near the route
- unload must come after pickup on route order

### Boarding rules

- request must be acknowledged first
- request must not be expired
- trip must be active
- passenger must board near the pickup reference

### Stop alert rules

- passenger must already be onboard
- active trip required
- repeated alerts are blocked during cooldown

## 26. Current UI and Map Behavior Notes

### Driver app current map behavior

- smooth animated jeep motion
- heading-aware vehicle rotation
- live-follow camera when user has not manually panned recently
- manual pan pauses follow, then follow resumes after cooldown

### Passenger app current map behavior

- smooth animated jeep motion from live updates
- heading-aware vehicle rotation
- selected route browsing shows at most 3 nearest eligible jeepneys
- jeepneys more than 100 meters ahead of the anchor on route progress are hidden
- onboarded jeep remains available for ride-specific tracking
- passenger auto-follow is focused on the onboarded jeep, not every route jeep

## 27. API Group Reference

Current API groups:

- `/auth`
- `/users`
- `/passengers`
- `/drivers`
- `/admin`
- `/jeepneys`
- `/routes`
- `/trips`
- `/pickup-requests`
- `/boarding`
- `/ride-sessions`
- `/stop-alerts`
- `/notifications`
- `/reports`

Important note:

- routes are mounted under `/api/v1`
- compatibility mounting also exists without `/api/v1`

## 28. Runtime Configuration

### Important backend environment variables

- `NODE_ENV`
- `PORT`
- `MONGO_URI`
- `JWT_SECRET`
- `JWT_EXPIRES_IN`
- `JWT_REFRESH_SECRET`
- `JWT_REFRESH_EXPIRES_IN`
- `BOARDING_WINDOW_MINUTES`
- `STOP_ALERT_COOLDOWN_MINUTES`
- `STOP_ALERT_ROAD_PROXIMITY_METERS`
- `UNLOAD_ROAD_PROXIMITY_METERS`
- `PICKUP_REQUEST_TTL_MINUTES`
- `MAX_REQUESTS_PER_PASSENGER_PER_TRIP`
- `PICKUP_ROAD_PROXIMITY_METERS`
- `PICKUP_CURRENT_LOCATION_MAX_DISTANCE_METERS`
- `JEEP_PASS_BY_REASSIGN_METERS`
- `FARE_BASE_AMOUNT`
- `FARE_BASE_DISTANCE_KM`
- `FARE_ADDITIONAL_AMOUNT_PER_KM`
- `GOOGLE_CLIENT_IDS`
- `FACEBOOK_APP_TOKEN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`
- `SMSAPIPH_API_KEY`
- `SMSAPIPH_BASE_URL`
- `TOMTOM_API_KEY`
- `GOOGLE_ROUTES_API_KEY`

### Important client runtime defines

- `PARAGO_API_BASE_URL`
- `PARAGO_API_BASE_URLS`
- `PARAGO_ENABLE_REALTIME`
- `PARAGO_GOOGLE_CLIENT_ID`
- `PARAGO_FACEBOOK_TOKEN`
- `ORS_API_KEY`

## 29. Deployment and Run Instructions

### Backend

1. Install dependencies with `npm install`
2. Fill root `.env`
3. Start development server with `npm run dev`
4. Start production server with `npm start`

### Admin web

1. Go to `parago_admin_web`
2. Run `flutter pub get`
3. Start with `flutter run -d chrome --dart-define=PARAGO_API_BASE_URL=<backend>/api/v1`

### Driver mobile

1. Go to `parago_mobile`
2. Run `flutter pub get`
3. Start with `flutter run -d <device> --dart-define=PARAGO_API_BASE_URL=<backend>/api/v1`

### Passenger mobile

1. Go to `parago_passenger`
2. Run `flutter pub get`
3. Start with `flutter run -d <device> --dart-define=PARAGO_API_BASE_URL=<backend>/api/v1`

## 30. Troubleshooting and Review Checklist

When reviewing the system with a group member, confirm the following:

- backend health endpoint responds
- database connection is valid
- admin can sign in
- routes exist and are active
- driver exists, is active, and is verified
- driver has an assigned jeepney
- driver has an assigned route when needed
- driver can create or start a trip
- driver app sends location successfully
- passenger sees active route and jeepneys
- passenger can pin valid pickup and unload points
- pickup request can be created
- driver can acknowledge the request
- passenger can validate boarding
- passenger can send stop alert while onboard
- driver can acknowledge the stop alert
- ride can be completed
- admin dashboard metrics update
- reports return data

## 31. Glossary

- Active trip: a trip session currently in operation and able to receive requests.
- Route snapshot: a stored copy of route geometry saved into a trip.
- Pickup request: a passenger booking request for a specific trip and route.
- Ride session: the onboard ride record created after successful boarding validation.
- Stop alert: a digital unload request, similar to a passenger saying "para".
- Route mode: standard roadside pickup operation.
- Terminal queue mode: terminal-based queue dispatch mode with queue numbering.

## 32. Final Summary

ParaGO is a multi-application transport operations platform where:

- admins configure the transport network
- drivers operate the live trips
- passengers request pickups, ride, and unload
- backend validations enforce safety and process rules
- notifications and realtime keep all roles synchronized

This document should be used as the main handoff and review guide for the current repository version.
