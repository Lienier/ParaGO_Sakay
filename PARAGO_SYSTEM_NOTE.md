# ParaGO System Note

Last updated: 2026-04-02

## Purpose

ParaGO is a multi-application transportation platform built around jeepney-style route operations. It is designed to support three coordinated user groups:

- Passengers who request pickup, track rides, and trigger stop alerts
- Drivers who manage trips, availability, requests, boarding, and unloading
- Admins who manage the transport network, driver/vehicle setup, routes, landmarks, and reports

This repository is not a single app. It is one backend plus three Flutter clients that all share the same API, database, and operational model.

## Repository Layout

- `src/`: Node.js + Express backend
- `parago_admin_web/`: Flutter web app for admin/staff
- `parago_mobile/`: Flutter mobile app for drivers
- `parago_passenger/`: Flutter mobile app for passengers
- `route_payloads/`: route-related payload references/generation artifacts
- `scripts/`: support scripts such as route payload generation
- `README.md` and per-app `README.md` files: setup-oriented summaries

## High-Level Architecture

### Backend

The backend is an Express application with:

- MongoDB via Mongoose
- JWT access tokens and refresh tokens
- Role-aware authorization
- Firebase Admin support for Google sign-in verification
- Optional Socket.IO realtime events
- REST endpoints under `/api/v1`
- Compatibility route registration without the `/api/v1` prefix for older clients

The backend entrypoints and core setup are:

- `src/server.js`: process startup
- `src/app.js`: middleware, health endpoints, route registration
- `src/config/apiRoutes.js`: central API route mounting
- `src/config/env.js`: runtime environment config

### Frontend

Each Flutter app follows a similar boot pattern:

1. Load `AppConfig`
2. Resolve a reachable API base URL
3. Initialize Firebase if supported/configured
4. Create an `ApiClient`
5. Restore locally stored tokens from `TokenStorage`
6. Use `SessionController` as the session/auth source of truth

All three clients use the same general pieces:

- `AppConfig`: runtime config from `--dart-define`
- `ApiClient`: HTTP access layer
- `SessionController`: login state, restore, refresh, logout
- `TokenStorage`: stores access/refresh tokens in local storage/shared preferences

## Main System Capabilities

At a system level, ParaGO currently supports:

- Account creation for passengers
- Email/password login for passenger, driver, and admin roles
- Firebase Google login for passenger-oriented flows
- Social login endpoints for Google and Facebook
- Admin OTP-backed login flow on the backend
- Driver account creation by admins
- Jeepney creation and assignment
- Route creation, update, geometry storage, deactivation, landmark management, and fare configuration
- Trip session scheduling and activation
- Driver online/offline availability behavior
- Passenger pickup request creation and driver acknowledgment
- Boarding validation tied to trip/request context
- Ride session lifecycle tracking
- Passenger stop alerts and driver acknowledgment
- Notifications and optional realtime delivery
- Admin dashboard metrics and reporting
- Activity logging for admin actions

## Applications And Their Responsibilities

### 1. Admin Web App: `parago_admin_web/`

The admin web app is the control panel for the operational side of ParaGO.

Primary responsibilities:

- Admin authentication
- Dashboard summary metrics
- Recent activity monitoring
- Driver and jeepney management
- Route creation and editing
- Landmark/stop management
- Fare configuration per route
- Reports for requests, boarding, alerts, trip activity, and route demand

Important behavior:

- It only accepts admin sessions
- It can use realtime admin events if `PARAGO_ENABLE_REALTIME=true`
- If realtime is disabled, it falls back to polling
- The default app home after login is `AdminHomeScreen`

Current admin workspace areas visible in code:

- Overview/dashboard
- Drivers
- Route builder
- Route management

### 2. Driver Mobile App: `parago_mobile/`

The driver app is the live operations console for a driver.

Primary responsibilities:

- Driver sign-in
- View assigned or active trips
- Start and end trips
- Toggle request acceptance / trip availability
- Monitor pickup requests
- Manage boarding-related state
- See route previews/maps
- Receive notifications/realtime updates
- Operate stop-alert-related flows
- Keep online presence aligned with session/app connectivity

Important behavior:

- Driver availability is automatically managed based on authentication state, app lifecycle, and connectivity
- Realtime is optional; otherwise the app uses timed refresh loops
- Driver authorization is strict around assigned trip/jeepney/route ownership

### 3. Passenger Mobile App: `parago_passenger/`

The passenger app is the commuter-facing client.

Primary responsibilities:

- Passenger registration and sign-in
- Route selection and trip selection
- Pickup request creation
- Pickup and destination pin placement
- Ride state monitoring
- Notifications
- Stop alert submission
- Passenger profile and ride history style flows

Important behavior:

- Pickup points must stay near the selected route and near the passenger's current location
- Destination points must stay on/near the route and must come after the pickup point along the route
- The passenger app can auto-handle some unload/stop-alert related behavior based on ride state and map distance logic

## Core Domain Model

The system is centered on a few main domain objects.

### User

`src/models/user.js`

Represents the shared identity record for all roles.

Key fields:

- `email`
- `passwordHash`
- `fullName`
- `phone`
- `role`: `PASSENGER`, `DRIVER`, `ADMIN`
- `authProvider`: `local`, `google`, `facebook`
- `providerId`
- `status`: `active`, `suspended`, `deactivated`
- `isVerified`
- `lastLoginAt`

### Passenger

`src/models/passenger.js`

Passenger profile extension on top of `User`.

Key fields:

- `userId`
- `phone`
- `photoUrl`
- `emergencyContact`
- `defaultRouteId`

### Driver

`src/models/driver.js`

Driver operational profile extension on top of `User`.

Key fields:

- `userId`
- `licenseNumber`
- `employeeNumber`
- `phone`
- `assignedJeepneyId`
- `assignedRouteId`
- `isVerified`
- `status`: `active`, `inactive`

### Admin

`src/models/admin.js`

Admin profile extension on top of `User`.

Used to represent admin-specific identity on top of the shared user record.

### Jeepney

`src/models/jeepney.js`

Represents a transport vehicle.

Key fields:

- `plateNumber`
- `capacity`
- `vehicleTag`
- `jeepneyName`
- `manufacturer`
- `capacityBand`
- `status`: `active`, `inactive`, `maintenance`
- `currentDriverId`
- `lastKnownLocation`
- `lastSeenAt`

### Route

`src/models/route.js`

Represents a transport route. This is one of the most important system entities because it is reused by all three apps.

Key fields:

- `name`
- `code`
- `direction`: `up`, `down`, `circular`
- `status`: `active`, `inactive`
- `description`
- `path`: GeoJSON line string for route geometry
- `waypoints`
- `stops`
- `navigation.origin`
- `navigation.destination`
- `navigation.bounds`
- `navigation.distanceMeters`
- `navigation.durationSeconds`
- `fareConfig.baseAmount`
- `fareConfig.baseDistanceKm`
- `fareConfig.additionalAmountPerKm`

Meaning in practice:

- Admins create and edit route geometry
- Drivers use routes for trip context and map previews
- Passengers use routes to select valid pickup and unload points
- Reports can group demand by route
- Route deactivation removes a route from active choices without deleting the record

### TripSession

`src/models/tripSession.js`

Represents a jeepney run tied to a driver, jeepney, and route.

Key fields:

- `jeepneyId`
- `driverId`
- `routeId`
- `routePathSnapshot`
- `status`: `scheduled`, `active`, `completed`, `cancelled`
- `startedAt`
- `endedAt`
- `acceptRequests`
- `occupancyCount`
- `active`
- `notes`

Important meaning:

- This is the live operating trip that passengers attach to
- Route geometry is snapshotted into the trip to preserve path context even if the route changes later

### PickupRequest

`src/models/pickupRequest.js`

Represents a passenger asking to be picked up for a specific trip and route.

Key fields:

- `passengerId`
- `tripSessionId`
- `routeId`
- `stopRef`
- `pickupLocation`
- `destinationStopRef`
- `destinationLocation`
- `fareSnapshot`
- `status`: `pending`, `acknowledged`, `completed`, `expired`, `cancelled`
- `acknowledgedBy`
- `acknowledgedAt`
- `sourceNote`
- `expiresAt`

Important meaning:

- Pickup requests are time-limited
- They are validated against route geometry and location rules
- They influence notifications, ride session creation, and admin metrics

### RideSession

`src/models/rideSession.js`

Represents the ride lifecycle once a pickup is transitioning into or is already an onboard trip.

Key fields:

- `passengerId`
- `tripSessionId`
- `pickupRequestId`
- `destinationStopRef`
- `destinationLocation`
- `fareSnapshot`
- `status`: `waiting`, `onboard`, `completed`
- `boardedAt`
- `endedAt`
- `canSendStopAlert`

### StopAlert

`src/models/stopAlert.js`

Represents the digital "para" / unload request sent while a ride is underway.

Key fields:

- `passengerId`
- `tripSessionId`
- `rideSessionId`
- `routeId`
- `stopRef`
- `note`
- `status`: `sent`, `seen`, `acknowledged`, `dismissed`
- `acknowledgedBy`
- `acknowledgedAt`
- `location`

### Notification

`src/models/notification.js`

Stores in-app notifications delivered to users and also used as the basis for realtime emissions.

### ActivityLog

`src/models/activityLog.js`

Stores admin activity and recent operational logs used by the admin dashboard.

### Supporting Security/Workflow Models

The backend also includes supporting models for:

- `refreshToken`
- `passwordResetToken`
- `adminLoginChallenge`
- `reportMetadata`

## Authentication And Session Flow

Authentication is role-aware and supports several paths.

### Supported auth flows

- Passenger self-registration with email/password
- Email/password login for all roles
- Admin backend OTP challenge flow
- Firebase Google login
- Social Google/Facebook login endpoints
- Refresh token rotation
- Password reset
- Password change

### Important rules

- Passenger self-registration is allowed
- Driver and admin accounts must be created by an admin
- Admin web only accepts admin sessions
- Driver operations check driver status and verification
- User status must be active to receive a session

### Session model

On successful login:

- The backend issues a JWT access token
- The backend issues a refresh token
- Refresh tokens are stored server-side with revocation/replacement tracking
- The client stores tokens locally
- The client can restore session with `/auth/me`
- If access token fails, the client attempts `/auth/refresh`

## API Surface

Main route groups mounted by the backend:

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

### Important endpoint behaviors

#### Auth

Implemented flows include:

- `POST /auth/register-email`
- `POST /auth/login-email`
- `POST /auth/admin/login/start`
- `POST /auth/admin/login/verify`
- `POST /auth/social/:provider`
- `POST /auth/firebase/google`
- `POST /auth/forgot-password`
- `POST /auth/reset-password`
- `POST /auth/refresh`
- `GET /auth/me`
- `POST /auth/logout`
- `POST /auth/change-password`

#### Admin

The admin API currently supports:

- dashboard summary metrics
- driver listing
- driver creation
- driver update
- jeepney assignment to drivers
- recent activity retrieval
- saved report metadata retrieval
- activity log creation

#### Routes

Route API currently supports:

- list routes
- create routes
- update routes
- deactivate routes

Important route behavior:

- Updating a route also updates the `routePathSnapshot` on scheduled/active trips that use that route
- Deactivation sets `status: inactive`; it is not a hard delete

#### Trips

Trip API currently supports:

- list active trips
- list driver-owned trips
- create trip
- start trip
- end trip
- change trip request availability
- list all trips

Important trip behavior:

- Drivers can only create or control trips they are allowed to operate
- Driver verification and assignment checks are enforced
- Active trips are used for passenger pickup eligibility

#### Pickup Requests

Pickup request API currently supports:

- create request
- list passenger's own requests
- list trip requests
- acknowledge request
- cancel request
- complete request

Important request behavior:

- Request creation validates route geometry and current passenger location
- The backend can automatically pick the best eligible trip on a route if one is not explicitly chosen
- Capacity and pending ride counts are considered when choosing a trip
- Request creation and state transitions trigger notifications

#### Boarding

Boarding API currently supports:

- validating a boarding attempt
- listing passenger ride sessions through the boarding route

Important boarding behavior:

- Boarding validation depends on trip, pickup request, passenger identity, location, and optional destination information
- Boarding is a bridge from pickup request state into ride session state

#### Ride Sessions

Ride session API currently supports:

- passenger ride session list
- trip ride session list
- ride completion

Important ride behavior:

- Only onboard rides can be completed
- Completing a ride dismisses active stop alerts tied to that ride

#### Stop Alerts

Stop alert API currently supports:

- create stop alert
- list stop alerts per trip
- acknowledge stop alert

Important stop alert behavior:

- Passenger sends alert while onboard
- Driver/admin can acknowledge
- Notifications are sent on both creation and acknowledgment

#### Notifications

Notification API currently supports:

- list my notifications
- mark one notification as read
- mark all notifications as read

#### Reports

Report API currently supports:

- pickup request status report
- boarding / ride session status report
- stop alert status report
- trip activity status report
- route demand report

These reports are date-range driven and optionally route-filtered where applicable.

## Main Operational Lifecycles

### 1. Admin Setup Lifecycle

Admin users can set up the operational network by:

1. Creating driver accounts
2. Creating or updating jeepneys
3. Assigning jeepneys to drivers
4. Creating routes with geometry and fare config
5. Adding route landmarks/stops
6. Assigning drivers to routes
7. Monitoring routes, demand, and activity

### 2. Route Lifecycle

Route management is a major part of the system.

Current route workflow:

1. Admin creates a route in the route builder
2. Start and end points are pinned on a map
3. A road-following path is built through the OpenStreetMap routing service
4. The route path, bounds, distance, duration, and fare config are saved
5. Landmarks/stops are added and snapped to the route
6. Landmarks are ordered along route progress
7. Landmark fares are derived from route distance
8. Route can be updated later
9. Route can be deactivated if no longer operational

Why this matters:

- Route geometry powers map previews, pickup validation, unload validation, stop placement, and trip snapshots

### 3. Driver Trip Lifecycle

Typical trip lifecycle:

1. Driver signs in
2. Driver views assigned/scheduled trips
3. Driver starts a trip
4. Trip becomes active and can accept passenger requests
5. Driver receives pickup requests and acknowledges them
6. Passenger boards through validated boarding flow
7. Ride sessions transition onboard
8. Passenger may send stop alerts
9. Driver ends the trip or completes ride sessions as appropriate

### 4. Passenger Ride Lifecycle

Typical passenger lifecycle:

1. Passenger signs in or registers
2. Passenger selects a route or active trip
3. Passenger chooses pickup and destination points
4. Backend validates location rules and finds an eligible trip
5. Pickup request is created
6. Driver acknowledges the request
7. Passenger boards through boarding validation
8. Ride session becomes active/onboard
9. Passenger sends stop alert when nearing destination
10. Driver or passenger completes the ride session

## Realtime And Notifications

Realtime is optional.

### Backend realtime behavior

`src/realtime/socketServer.js`

The backend:

- authenticates Socket.IO connections using the normal JWT access token
- joins users to user-specific rooms
- joins users to role-based rooms
- emits user notification events
- emits admin operations events

Current notable event channels:

- `notification.created`
- `ops.changed`

### How notifications are published

`src/services/notificationPublisher.js`

When domain actions occur, the backend:

1. Creates a `Notification` document
2. Emits the notification to the target user room
3. Emits an operations event for admins

This means admin dashboards can react to operational events while individual users also receive their own notifications.

### Frontend fallback behavior

If realtime is disabled:

- admin screens poll on intervals
- driver screens use live refresh loops
- passenger screens use refresh loops and cached snapshots

## Validation And Operational Rules

Several important rules are encoded in the backend and client apps.

### Request and route rules

- pickup must be near the selected route
- destination must be near the selected route
- destination must come after pickup along the route
- pickup must be near the passenger's current location
- only active trips that accept requests are eligible
- capacity is checked before assigning a trip

### Driver rules

- driver account must be active
- driver may need to be verified for trip creation/start
- assigned jeepney and route restrictions are enforced

### Ride rules

- only valid pickup/trip contexts can become boarded rides
- only onboard rides can be completed
- active stop alerts are dismissed when a ride completes

### Request lifetime rules

- pickup requests expire automatically with MongoDB TTL behavior on `expiresAt`
- repeated pending requests per passenger/trip are limited by config

## Configuration And Environment

Important backend environment values in `src/config/env.js` include:

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

Important frontend runtime defines include:

- `PARAGO_API_BASE_URL`
- `PARAGO_API_BASE_URLS`
- `PARAGO_GOOGLE_CLIENT_ID`
- `PARAGO_FACEBOOK_TOKEN`
- `ORS_API_KEY`
- `PARAGO_ENABLE_REALTIME`

## Mapping And Geometry

Route geometry is a major part of the current system design.

Current route/map-related behavior includes:

- OpenStreetMap route generation in admin route builder
- cached/offline-ready route snapshots
- route path snapshots copied into trip sessions
- landmark snapping to route geometry
- route-aware pickup validation
- route-aware destination validation
- route-aware ordering of pickup and unload points
- route-aware fare snapshot calculation

This is one of the strongest architectural through-lines in the repository: route geometry is not cosmetic, it is operational data.

## Reporting

Admin reporting currently focuses on operational summaries rather than deep BI.

Current reports include:

- total and by-status pickup requests
- total and by-status boarding/ride sessions
- total and by-status stop alerts
- total and by-status trip activity
- route demand ranking by number of pickup requests

The admin home screen also uses dashboard snapshots such as:

- active trips
- pending requests
- onboard rides
- active alerts

## Security And Access Model

Important security patterns:

- authentication middleware protects private routes
- authorization middleware checks role access
- refresh tokens are revocable and rotated
- admin, driver, and passenger responsibilities are separated
- admin-only functions are isolated under admin routes and admin web UX

Current practical notes:

- tokens are stored client-side in local storage/shared preferences
- the readmes note that secure storage can be added later for stronger hardening
- auth rate limiting exists in the backend

## Current Known Design Characteristics

These are not necessarily bugs; they are important traits of the current system:

- Route deletion is soft through deactivation, not hard delete
- Realtime is optional, not mandatory
- The backend supports admin OTP login, but the current admin web UI shown in the repo uses direct email/password admin login
- The backend supports Firebase/social login, but the most visible usage is passenger-oriented
- Route geometry and snapshots are treated as shared truth across operational workflows
- Compatibility API mounting exists for clients that temporarily omit `/api/v1`
- In development, forgot-password can return a temporary reset token to avoid blocking testing when SMTP is not configured

## Best Starting Points For Future Codex Sessions

If a future Codex session needs to understand the project quickly, these are the highest-value entry files:

- `README.md`
- `src/app.js`
- `src/config/apiRoutes.js`
- `src/config/env.js`
- `src/services/auth.service.js`
- `src/routes/routes.routes.js`
- `src/routes/trips.routes.js`
- `src/routes/pickupRequests.routes.js`
- `src/routes/boarding.routes.js`
- `src/routes/rideSessions.routes.js`
- `src/routes/stopAlerts.routes.js`
- `src/realtime/socketServer.js`
- `parago_admin_web/lib/main.dart`
- `parago_admin_web/lib/screens/admin/admin_home_screen.dart`
- `parago_admin_web/lib/screens/admin/admin_route_management_screen.dart`
- `parago_admin_web/lib/screens/admin/admin_route_builder_screen.dart`
- `parago_admin_web/lib/screens/admin/admin_route_landmark_editor_screen.dart`
- `parago_mobile/lib/screens/driver/driver_home_screen.dart`
- `parago_passenger/lib/screens/passenger/passenger_home_screen.dart`

## Short Summary

ParaGO is a shared transport operations platform built as:

- one Express/MongoDB backend
- one admin Flutter web app
- one driver Flutter mobile app
- one passenger Flutter mobile app

Its core business flow is:

1. admins set up routes, drivers, and vehicles
2. drivers run trips on routes
3. passengers request pickup on active trips
4. boarding creates ride state
5. stop alerts manage unloading
6. notifications and optional realtime keep all parties updated
7. admin dashboards and reports summarize activity

If you need to continue work in this repository from a fresh session, this file is intended to be the fastest full-system handoff note.
