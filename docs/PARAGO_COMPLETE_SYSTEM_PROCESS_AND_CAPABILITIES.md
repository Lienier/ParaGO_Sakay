# ParaGO Complete System Process And Capabilities

Last updated: 2026-07-29

## 1. Purpose Of This Document

This document is the main end-to-end guide for the ParaGO system. It explains what the system does, what each app is responsible for, how the main processes work, what must be configured for each feature to work, what state changes happen in the backend, what users should see, and what fallback behavior exists when GPS, internet, or operational data is incomplete.

Use this document when you need to understand the full ParaGO workflow from admin setup to passenger ride completion.

For focused implementation details, see the related documents listed at the end of this file.

## 2. System Overview

ParaGO is a jeepney transportation operations system. It connects three user groups:

- Admins, who configure and monitor the transport operation, publish service announcements, and answer support threads.
- Drivers, who operate jeepney trips, handle passenger requests, receive announcements, and contact admin support.
- Passengers, who book and track rides, view live jeep details and ETA, receive announcements, and contact admin support.

The repository contains one backend and three Flutter clients:

- `src/`: Node.js and Express backend.
- `parago_admin_web/`: Flutter web app for admins.
- `parago_mobile/`: Flutter mobile app for drivers.
- `parago_passenger/`: Flutter mobile app for passengers.

The backend is the source of truth. The apps display and update backend state through REST API calls and optional realtime events.

## 3. Main System Goal

The system is designed to support a jeepney ride lifecycle:

1. Admin prepares drivers, jeepneys, routes, terminals, landmarks, and fares.
2. Driver logs in, goes online, and starts a route or terminal queue trip.
3. Passenger logs in, selects a route, and sends a roadside or terminal pickup request.
4. Backend validates the request and assigns it to an eligible trip.
5. Driver acknowledges the request.
6. Passenger boards manually or is automatically marked onboard when near the jeepney long enough.
7. Backend creates or updates the ride session and increases passenger count.
8. Passenger rides, watches route/trip status, and can send a digital para/stop alert.
9. Passenger unloads manually or is automatically marked offboard after separation from the jeepney.
10. Backend completes the ride session and decreases passenger count.
11. Passenger or driver can contact admin support when an issue needs assistance.
12. Admin can publish targeted service announcements and manage support conversations.
13. Admin monitors operations, reports, dashboard metrics, and terminal queue behavior.

## 4. What Must Exist For The System To Work

The system needs both technical setup and operational setup.

### 4.1 Technical Requirements

The backend needs:

- Node.js runtime.
- Express server running from `src/server.js`.
- MongoDB connection through `MONGO_URI`.
- JWT configuration through `JWT_SECRET`.
- Refresh-token configuration through `JWT_REFRESH_SECRET` or fallback to `JWT_SECRET`.
- Route registration through `src/config/apiRoutes.js`.
- Optional Firebase configuration if Firebase Google login is used.
- Optional Socket.IO support if realtime behavior is enabled in deployment.
- `GOOGLE_ROUTES_API_KEY` when Google route previews or passenger traffic ETA are required.
- Google Cloud billing with the Google Routes API enabled. ParaGO does not require every Google Maps Platform API.

The client apps need:

- Flutter runtime/tooling for building the apps.
- Correct API base URL through app configuration or build-time defines.
- Local token storage support for persistent login.
- Internet access to reach the backend.
- Location permission for driver GPS, passenger location reporting, automatic onboarding, automatic offboarding, route proximity checks, and stop/unload checks.
- `flutter_map` and the existing OSM tile/map configuration for visual map rendering.

Google Routes API is a backend routing and ETA provider. It does not replace `flutter_map`, and the Google API key must never be embedded in a Flutter client.

### 4.2 Operational Requirements

Before live operations work correctly, admins must set up:

- Admin account access.
- Driver accounts.
- Jeepney records.
- Driver to jeepney assignment.
- Driver to route assignment where required.
- Active routes with route geometry.
- Route stops/landmarks.
- Fare configuration if fare calculation is needed.
- Terminal configuration if terminal queue mode will be used.

Before a passenger can ride, the system generally needs:

- An active route.
- An active or scheduled trip that can accept requests.
- A driver operating the trip.
- A passenger account.
- Passenger location permission.
- Pickup and destination/unload information.

Before automatic onboarding/offboarding can work, the system needs:

- Acknowledged pickup request for onboarding.
- Onboard ride session for offboarding.
- Recent passenger location.
- Recent driver/jeepney location.
- Stable enough network to send location updates.
- GPS values that are not stale or invalid.

## 5. High-Level Architecture

### 5.1 Backend API Layer

The backend exposes API groups under `/api/v1`, with compatibility registration also available without the prefix for older clients.

The main API groups are:

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
- `/announcements`
- `/support`
- `/reports`

The backend handles:

- Authentication.
- Authorization.
- Data validation.
- MongoDB persistence.
- Route geometry rules.
- Request assignment.
- Boarding and ride completion.
- Terminal queue state.
- Passenger count changes.
- Notification creation.
- Traffic-aware route previews and passenger ETA where Google Routes API is configured.
- Support thread/message authorization and persistence.
- Announcement scheduling, targeting, revision, dismissal, and lifecycle reconciliation.
- Optional realtime broadcasting.

### 5.2 Database Layer

MongoDB stores the operational state. Mongoose models define the data shape and indexes.

Important model groups:

- Identity: `User`, `Passenger`, `Driver`, `Admin`.
- Transport setup: `Jeepney`, `Route`.
- Live operations: `TripSession`, `PickupRequest`, `RideSession`, `StopAlert`.
- Messaging and logs: `Notification`, `SupportThread`, `SupportMessage`, `Announcement`, `AnnouncementDismissal`, `ActivityLog`.
- Security/workflow: `RefreshToken`, `PasswordResetToken`, `AdminLoginChallenge`.

### 5.3 Auth And Authorization Layer

Auth uses JWT access tokens and refresh tokens. The access token is used for normal API calls. The refresh token lets the app restore or renew the session without asking the user to log in every time.

Authorization checks role-specific access:

- Admin-only actions are restricted to admin users.
- Driver-only actions are restricted to driver users.
- Passenger-only actions are restricted to passenger users.
- Shared endpoints still validate ownership and role before returning or changing sensitive data.

### 5.4 Notification And Realtime Layer

The backend can create notifications and publish operational events.

Notifications are durable records that users can fetch later.

Realtime events are optional and allow clients to update faster when Socket.IO is available. Authenticated sockets join user and role rooms, while passenger/driver map flows can also subscribe to route and trip rooms.

Support and announcement clients reconcile from the API after relevant socket events and after `socket.ready`. Network failures preserve the socket context and schedule another connection attempt after 15 seconds. When realtime remains unavailable, support and announcement views use 30-second polling.

### 5.5 Client App Layer

All Flutter apps follow the same general pattern:

1. Load app configuration.
2. Resolve the API base URL.
3. Restore stored tokens.
4. Ask the backend who the current user is.
5. Enforce the correct role for the app.
6. Display the role-specific home screen.
7. Use services to call backend APIs.
8. Use cached data and refresh loops where appropriate.
9. Keep core trip/dashboard loading independent from best-effort announcement loading.
10. Reconcile support and announcements after realtime events and reconnects.

GET requests can be coalesced and cached according to their volatility. Support, announcement, and notification mutations invalidate only their own cache groups. Cross-domain trip and booking mutations continue to clear the broader cache. A cache generation prevents an older GET response from writing stale data after a newer mutation.

## 6. Core Data Models

### 6.1 User

The `User` model is the shared identity record.

It stores:

- Email.
- Password hash.
- Full name.
- Phone.
- Role: `PASSENGER`, `DRIVER`, or `ADMIN`.
- Auth provider: local, Google, or Facebook.
- Account status.
- Verification state.
- Last login timestamp.

How it is used:

- Every role starts with a `User`.
- The role decides which app the user may access.
- A user can be blocked from access if suspended or deactivated.

### 6.2 Passenger

The `Passenger` model extends a user into a passenger profile.

It stores:

- User reference.
- Phone and profile information.
- Emergency contact.
- Default route information.
- Last known location.
- Last seen time.

How it is used:

- Passenger booking validation depends on the passenger profile.
- Automatic onboarding and offboarding use the passenger last known location.
- Passenger-owned requests, rides, stop alerts, and notifications are filtered by passenger identity.

### 6.3 Driver

The `Driver` model extends a user into a driver profile.

It stores:

- User reference.
- License and employee information.
- Assigned jeepney.
- Assigned route.
- Verification state.
- Status.
- Terminal queue operating state.

How it is used:

- Driver login only works for driver users.
- Trip operations check driver ownership and assignments.
- Terminal queue state can be mirrored between driver and active trip.
- Driver location updates are used by passenger maps and ride automation.

### 6.4 Admin

The `Admin` model represents admin-specific identity.

How it is used:

- Admin web access requires an admin role.
- Admin APIs require admin authorization.
- Admin actions can create activity logs and operational changes.

### 6.5 Jeepney

The `Jeepney` model represents the vehicle.

It stores:

- Plate number.
- Capacity.
- Status.
- Current location where available.
- Assignment-related information.

How it is used:

- Trips are tied to jeepneys.
- Capacity checks use jeepney capacity and trip occupancy.
- Driver assignment determines which jeepney a driver can operate.
- Location may be used for operations and display.

### 6.6 Route

The `Route` model represents a transport route.

It stores:

- Name and code.
- Direction.
- Status.
- LineString path geometry.
- Stops or landmarks.
- Bounds.
- Fare configuration.
- Terminal settings.

How it is used:

- Passengers select routes.
- Trips operate on routes.
- Pickup and destination locations are validated against route geometry.
- Stops and landmarks are used for boarding/unloading references.
- Terminal settings determine terminal queue support.

### 6.7 Route Terminal Settings

The `terminal` object on a route defines terminal behavior.

It can contain:

- `enabled`: whether terminal queue support is enabled.
- `name`: admin-facing terminal name.
- `stopRef`: operational terminal label.
- `location`: terminal coordinate.
- `radiusMeters`: geofence radius for terminal behavior and UI.

How it is used:

- Terminal passenger booking uses the terminal location.
- Terminal queue trips use the terminal stop reference and location.
- Admins can set or adjust the terminal from the route management UI.
- If no explicit terminal is configured, the system can fall back to the first valid route stop.

### 6.8 TripSession

The `TripSession` model represents one operating jeepney trip.

It stores:

- Jeepney reference.
- Driver reference.
- Route reference.
- Route path snapshot.
- Status: `scheduled`, `active`, `completed`, or `cancelled`.
- Start and end time.
- Request acceptance flag.
- Manual occupancy count.
- Occupancy count.
- Operating mode: `route` or `terminal_queue`.
- Terminal queue status: `off_queue`, `waiting`, `loading`, `skipped`, or `departed`.
- Terminal queue number.
- Terminal check-in time.
- Terminal stop and location.

How it is used:

- Active trips receive pickup requests.
- Occupancy count tells the driver/admin how many passengers are onboard.
- Terminal queue trips are ordered by status and queue number.
- Automatic onboarding and offboarding change occupancy count through ride state changes.

### 6.9 PickupRequest

The `PickupRequest` model represents a passenger asking to ride.

It stores:

- Passenger reference.
- Trip reference.
- Route reference.
- Pickup type: roadside or terminal.
- Pickup location.
- Destination/unload location.
- Status: pending, acknowledged, completed, expired, or cancelled.
- Fare snapshot.
- Auto-boarding state.
- Expiry information.

How it is used:

- It is created when a passenger books.
- It becomes acknowledged when the driver accepts/acknowledges it.
- It becomes completed when boarding creates or activates the ride session.
- It can expire automatically or be cancelled.
- Automatic onboarding reads the acknowledged request and proximity state.

### 6.10 RideSession

The `RideSession` model represents the passenger's ride.

It stores:

- Passenger reference.
- Trip session reference.
- Pickup request reference.
- Pickup type.
- Boarding method: `manual` or `auto_proximity`.
- Boarding location and stop.
- Destination/unload location and stop.
- Fare snapshot.
- Status: `waiting`, `onboard`, or `completed`.
- Offboarding method: `manual` or `auto_separation`.
- Auto-offboarding state.
- Boarded time.
- Ended time.
- Stop-alert permission.
- Destination approach alert state.

How it is used:

- It connects the passenger to a trip after boarding starts.
- Stop alerts require an onboard ride.
- Ride completion decreases passenger count.
- Boarding/offboarding method fields explain whether the process was manual or automatic.

### 6.11 StopAlert

The `StopAlert` model represents a digital para or unload alert.

It stores:

- Passenger.
- Driver/trip context.
- Ride session.
- Destination/unload location.
- Status such as sent, seen, acknowledged, or dismissed.

How it is used:

- Passengers send stop alerts while onboard.
- Drivers can acknowledge alerts.
- Active alerts are dismissed when the ride completes.

### 6.12 Notification

The `Notification` model stores user-facing events.

How it is used:

- Passenger receives ride/request updates.
- Driver receives pickup, boarding, and unload updates.
- Admin may receive operations events depending on realtime and dashboard behavior.
- Apps can fetch unread notifications and mark them read.

### 6.13 RefreshToken

The `RefreshToken` model supports one-time login behavior.

It stores refresh-token state as hashes, not raw tokens.

How it is used:

- App startup can restore sessions.
- Refresh tokens can be rotated.
- Old refresh tokens can be revoked.
- Manual logout can invalidate the session.

### 6.14 ActivityLog

The `ActivityLog` model stores admin or system activity.

How it is used:

- Admin dashboard can show recent activity.
- Operational actions can be reviewed later.

### 6.15 SupportThread

The `SupportThread` model represents a two-way support conversation between one passenger or driver and the admin team.

It stores:

- Owning user and user role.
- Optional assigned admin.
- Subject and category.
- Status: `open`, `awaiting_admin`, `awaiting_user`, `resolved`, or `closed`.
- Optional trip, pickup request, ride session, and route context.
- Last-message preview and sender role.
- Separate user/admin unread counts and read timestamps.
- Resolution, closure, and reopening audit fields.

Only the owner and admins can access a thread. Closed threads must be reopened before another message is accepted.

### 6.16 SupportMessage

The `SupportMessage` model stores one text message in a support thread.

It stores:

- Thread reference.
- Sender identity.
- Sender role: `PASSENGER`, `DRIVER`, or `ADMIN`.
- Text body.
- Creation timestamp.

Version 1 is text-only. File attachments and voice notes are not part of the current implementation.

### 6.17 Announcement

The `Announcement` model stores one role-targeted service notice.

It stores:

- Title and body.
- Category: `service_change`, `disruption`, `maintenance`, `safety`, or `general`.
- Severity: `info`, `warning`, or `critical`.
- Passenger, driver, or shared audiences.
- Status: `scheduled`, `published`, `expired`, or `archived`.
- Revision number.
- UTC start and optional expiry timestamps.
- Creator and last-editor audit fields.

Expired and archived announcements are immutable. An expired announcement can be duplicated through the create flow as a new record with revision `1`.

### 6.18 AnnouncementDismissal

The `AnnouncementDismissal` model records that a user dismissed a specific announcement revision.

The unique identity is:

- Announcement.
- User.
- Revision.

A later published edit increments the revision and becomes visible again even if the user dismissed an older revision.

## 7. Authentication And One-Time Login

### 7.1 What The Feature Does

One-time login means the user should not need to type email and password every time the app restarts.

After a successful login, the app stores tokens locally. On the next app launch, the app tries to restore the session using those stored tokens.

This does not mean the session lasts forever. It means the app can keep the user signed in while the refresh token remains valid and not revoked.

### 7.2 Who Uses It

All user groups benefit from it:

- Admins in the admin web app.
- Drivers in the driver mobile app.
- Passengers in the passenger mobile app.

### 7.3 What Must Exist Before It Works

The feature requires:

- Successful login.
- Valid JWT configuration.
- Valid refresh token configuration.
- Client token storage.
- Backend refresh endpoint.
- User account still active.
- Role still allowed for the app being opened.

### 7.4 Normal Login Process

1. User submits credentials.
2. Backend validates email/password or social/Firebase identity.
3. Backend checks user status and role.
4. Backend issues an access token.
5. Backend issues a refresh token.
6. Backend stores refresh token state as a hash.
7. Client stores tokens locally.
8. Client loads the correct app home screen.

### 7.5 App Restart Process

1. App starts.
2. App reads stored token data from local storage.
3. App asks the backend to confirm or refresh the session.
4. If the access token is still valid, API calls continue.
5. If the access token expired but refresh token is valid, backend rotates the refresh token and sends new token data.
6. Client stores the replacement token data.
7. User stays signed in.

### 7.6 Token Rotation

Refresh token rotation means the old refresh token is replaced with a new one. The old token is marked revoked and linked to the replacement hash.

This reduces risk because an older refresh token should not remain usable after a new token is issued.

### 7.7 Logout Behavior

When the user logs out:

1. Client calls logout.
2. Backend revokes the refresh token where applicable.
3. Client clears local tokens.
4. App returns to the auth screen.
5. The user must log in again to create a new session.

### 7.8 Role Guarding

Each app verifies that the restored account has the correct role.

Examples:

- Passenger app rejects admin or driver accounts.
- Driver app rejects passenger or admin accounts.
- Admin web rejects passenger or driver accounts.

This prevents a valid token from being used in the wrong client.

### 7.9 What Can Prevent It From Working

One-time login can fail when:

- Local tokens were cleared.
- Refresh token expired.
- Refresh token was revoked by logout.
- JWT secrets changed on the backend.
- User was suspended or deactivated.
- User opens the wrong role app.
- Backend is unreachable during restore.

### 7.10 How To Verify

1. Log in successfully.
2. Close the app or browser tab.
3. Reopen it.
4. Confirm the app restores the session without asking for credentials.
5. Log out manually.
6. Reopen the app.
7. Confirm it asks for login again.

More detail: [ONE_TIME_LOGIN.md](ONE_TIME_LOGIN.md).

## 8. Admin System Process

### 8.1 What Admins Control

Admins control the operational setup of ParaGO.

Admins can manage:

- Drivers.
- Jeepneys.
- Driver to jeepney assignments.
- Routes.
- Route landmarks/stops.
- Route fares.
- Route terminal settings.
- Dashboard monitoring.
- Terminal queue dispatch board.
- Shared passenger/driver support inbox.
- Service announcement workspace.
- Reports.
- Recent activity.

### 8.2 Admin Login

The admin logs in through the admin web app. The app checks that the restored or newly authenticated user has the admin role.

If the account is not admin, the app should not allow access to the admin workspace.

### 8.3 Admin Dashboard

The dashboard gives an operations overview.

It can show:

- Summary metrics.
- Active operations.
- Recent activity.
- Terminal dispatch board.
- Waiting passengers.
- Route-mode drivers.
- Current terminal queue state.

The dashboard may use realtime events when available. If not, it relies on refresh/polling behavior.

### 8.4 Driver Management

Admin driver management includes:

- Viewing drivers.
- Creating drivers.
- Updating driver profile fields.
- Assigning jeepneys.
- Reviewing driver route/vehicle assignments.
- Checking driver operational status.

What must exist:

- Admin session.
- Backend admin API.
- Driver user/profile data.
- Jeepney data for assignment.

Backend result:

- Driver profile is created or updated.
- Related user identity remains role-protected.
- Assignment fields are stored for driver operations.

### 8.5 Jeepney Management

Jeepney management includes:

- Creating jeepney records.
- Editing jeepney information.
- Setting active, inactive, or maintenance status.
- Assigning a jeepney to a driver.
- Using capacity for trip and passenger count logic.

What must exist:

- Admin session.
- Jeepney plate/capacity information.
- Driver assignment if the jeepney will be operated.

### 8.6 Route Creation And Management

Routes are the foundation of passenger booking and driver trips.

Admins can:

- Create routes.
- Edit route name/code/direction/status.
- Define route path geometry.
- Add landmarks/stops.
- Configure fares.
- Configure terminal settings.
- Deactivate routes when no longer used.

What must exist:

- Admin session.
- Valid route geometry.
- Valid stop/landmark data if stops are used.
- Active status for passenger visibility and trip operations.

Backend result:

- Route data is stored.
- Trip creation can reference the route.
- Passenger booking validates against route geometry.
- Terminal queue behavior can use the route terminal.

### 8.7 Landmark And Fare Management

Landmarks/stops help the system understand boarding and destination positions.

Fare configuration helps calculate fare snapshots for pickup requests and rides.

The fare snapshot is important because it preserves fare information from the time of request/boarding rather than relying only on future route changes.

### 8.8 Terminal Settings Management

Admins configure terminal settings from route management.

They can:

- Enable or disable terminal support.
- Set terminal name.
- Set terminal operational label.
- Select a terminal from an existing route landmark.
- Place a custom terminal pin on the map.
- Set terminal radius.
- Save terminal settings without changing route geometry.

Terminal settings are described in detail in section 9.

### 8.9 Reports

Reports help admins review operations.

Report categories include:

- Requests.
- Boarding.
- Alerts.
- Trip activity.
- Route demand.
- Passenger flow.

Reports are useful for:

- Seeing demand patterns.
- Reviewing problem areas.
- Checking boarding and alert volumes.
- Understanding route usage.
- Supporting operational decisions.

### 8.10 Support Inbox

The admin support workspace is a shared inbox for passenger and driver concerns.

Admins can:

- Filter by status, category, user role, and closed state.
- Select a thread and read its full message history.
- Reply to the user.
- Assign or take ownership of a thread.
- Resolve, close, or reopen a thread.
- Review optional trip, pickup request, ride session, and route context.

The desktop layout uses a bounded, lazy inbox list and a separate detail pane. Narrow web widths show the list first and open detail in a sheet. Long subjects, previews, and complete messages wrap within constrained layouts to prevent render overflow and browser freezes.

Realtime events refresh the inbox quickly. A silent 30-second API refresh remains active as fallback, and request generations prevent older responses from replacing newer filter or thread state.

### 8.11 Announcement Workspace

Admins use the announcement workspace to create service changes, disruptions, maintenance notices, safety notices, and general updates.

Admins can:

- Target passengers, drivers, or both.
- Publish immediately or schedule a UTC start time from browser-local controls.
- Set an optional expiry.
- Choose info, warning, or critical severity.
- Filter and paginate announcement history.
- Edit scheduled or published announcements.
- Duplicate an expired announcement into a new record.
- Archive any non-archived announcement.

The admin API uses a default page size of `25` and a maximum of `50`. List rows show bounded previews; the complete body is rendered only in the selected detail pane.

Critical create/update operations require `confirmCritical: true`. Archiving a currently active announcement requires `confirmActiveArchive: true`. The UI sends those flags only after the admin accepts the matching confirmation dialog.

## 9. Terminal Settings

### 9.1 What Terminal Settings Are

Terminal settings define the exact terminal location and terminal behavior for a route.

Without explicit terminal settings, the system may fall back to the first valid route stop. Explicit settings are better because the terminal is operationally important and may not always be the first route landmark.

### 9.2 Why They Are Needed

Terminal settings support:

- Terminal passenger booking.
- Terminal queue mode.
- Admin terminal dispatch board.
- Correct terminal pickup location.
- Terminal queue trip validation.
- Future geofence-based terminal checks.

### 9.3 What Must Exist Before It Works

Terminal settings require:

- Active route.
- Admin access.
- Route management UI.
- Terminal coordinates or a valid fallback route stop.
- Terminal enabled if terminal queue support should be available.

### 9.4 Terminal Enabled/Disabled Behavior

If terminal settings are disabled:

- Terminal queue support is disabled for that route.
- Terminal booking should not be treated as supported for that route.
- The route may still work for normal roadside operations.

If terminal settings are enabled:

- The route can support terminal queue operations.
- The configured terminal location is preferred.
- If no explicit location exists, the system can use fallback behavior.

### 9.5 Terminal Name

The terminal name is admin-facing. It helps staff identify the real terminal.

Example use:

- Admin sees the named terminal in route management.
- Dispatchers can confirm which physical location the route uses.

### 9.6 Terminal Stop Label

The terminal stop reference is the operational label used by requests and trip sessions.

It helps connect:

- Passenger terminal booking.
- Trip terminal queue fields.
- Boarding stop references.
- Reports and operational display.

### 9.7 Terminal Location

The terminal location is a coordinate stored as a GeoJSON point style coordinate.

It is used by:

- Terminal pickup location.
- Terminal queue trip state.
- Admin map display.
- Future or current geofence/radius checks.

### 9.8 Terminal Radius

The terminal radius defines a meter-based area around the terminal.

It is useful for:

- Showing the operational terminal area.
- Future proximity validation.
- Making clear that the terminal is not just a single pixel on the map.

### 9.9 Terminal Resolution Rule

When the backend needs a terminal for a route:

1. If terminal support is disabled, the route has no terminal queue support.
2. If configured terminal location exists, use that terminal.
3. If no explicit location exists, use the first valid route stop as fallback.

This keeps older routes usable while allowing precise terminal setup for routes that need it.

### 9.10 User-Facing Result

Admins should see:

- Terminal settings button or dialog in route management.
- Map selection for terminal placement.
- Terminal metadata fields.
- Whether the route is using configured terminal or fallback terminal.

Passengers should see:

- Terminal booking availability only when the route supports terminal behavior.
- Terminal pickup point based on route terminal.

Drivers should see:

- Terminal queue behavior only for routes with terminal support.

### 9.11 What Can Prevent It From Working

Terminal behavior can fail or be unavailable when:

- Route has no terminal settings and no valid fallback stop.
- Terminal support is disabled.
- Route is inactive.
- Admin saves invalid coordinates.
- Client has stale route data.

### 9.12 How To Verify

1. Open admin route management.
2. Select a route.
3. Open terminal settings.
4. Enable terminal support.
5. Set terminal name and label.
6. Place terminal on the map or select an existing landmark.
7. Save.
8. Reload the route.
9. Confirm terminal settings remain.
10. Start terminal queue behavior for that route.

More detail: [TERMINAL_SETTINGS.md](TERMINAL_SETTINGS.md).

## 10. Terminal Queue Management

### 10.1 What The Jeepney Queue Is

The terminal queue is the ordered list of jeepneys waiting or loading at a terminal.

It models the real terminal dispatch process where jeepneys line up, load passengers, and depart in order.

### 10.2 Who Uses It

Admins use it to monitor and manage queue order.

Drivers participate in it when their trip operates in terminal queue mode.

Passengers are affected by it when they book from a terminal because their request should go to an eligible terminal queue jeepney.

### 10.3 What Must Exist Before It Works

Terminal queue management requires:

- Route with terminal support.
- Driver account.
- Assigned jeepney.
- Trip session in terminal queue mode.
- Terminal queue status and queue number.
- Admin dashboard access for the dispatch board.

### 10.4 Queue States

The queue uses these states:

- `off_queue`: jeepney is not currently part of the terminal queue.
- `waiting`: jeepney is waiting in queue.
- `loading`: jeepney is actively receiving or assigned terminal passengers.
- `skipped`: jeepney remains visible but is skipped for new terminal passenger assignment.
- `departed`: jeepney has left the queue.

### 10.5 Sorting Behavior

The admin board sorts terminal queue trips by operational priority:

1. Loading trips.
2. Waiting trips.
3. Skipped trips.
4. Departed trips.
5. Queue number/order within those groups.

This keeps active loading jeepneys visible first, while skipped jeepneys remain visible for staff review.

### 10.6 Admin Terminal Dispatch Board

The admin overview dashboard includes a terminal dispatch board.

It can show:

- Active terminal queue jeepneys.
- Queue number.
- Driver/jeepney information.
- Queue status.
- Waiting terminal passengers.
- Route-mode drivers outside the queue.
- Controls to move queue entries.
- Controls to skip or restore a jeepney.

### 10.7 Reorder Behavior

Admins can move a terminal queue trip up or down.

Backend result:

- Queue numbers are adjusted safely.
- The selected trip changes position.
- The board refreshes and shows the new order.
- Passenger assignment uses the updated order for future terminal bookings.

User result:

- Admin sees the jeepney move in the queue.
- Driver/passenger assignment behavior follows the new queue order.

### 10.8 Skip Behavior

Admins can skip a jeepney.

Backend result:

- Queue status becomes `skipped`.
- The jeepney remains visible.
- The jeepney is excluded from new terminal passenger assignment.
- Existing state can still be reviewed.

User result:

- Admin sees the skipped jeepney.
- New terminal passengers are not assigned to that skipped jeepney.

Common reasons to skip:

- Driver is temporarily unavailable.
- Jeepney needs inspection.
- Jeepney is not ready to load.
- Dispatch wants another jeepney to load first.

### 10.9 Restore Behavior

Admins can restore a skipped jeepney.

Backend result:

- Jeepney returns to active queue handling.
- Restored jeepney goes to the back of the active queue.
- If it already has acknowledged terminal passengers, it can return to loading.
- Otherwise it returns to waiting.

User result:

- Admin sees the jeepney back in active queue order.
- Future terminal passengers can be assigned to it again.

### 10.10 Waiting Terminal Passengers

The dispatch board can show waiting terminal passengers linked to terminal queue trips.

This helps admins understand:

- Which passengers are waiting.
- Which route/terminal flow they belong to.
- Whether loading state matches passenger demand.

### 10.11 Route-Mode Drivers

The board can also show route-mode drivers operating outside terminal queue mode.

This helps admins separate:

- Drivers currently serving roadside/route operations.
- Drivers currently part of terminal dispatch.

### 10.12 How Queue Changes Affect Passenger Assignment

Terminal passenger assignment should prefer eligible terminal queue trips.

Skipped trips are ignored for new terminal passenger assignment. This is important because skipped means the jeepney is intentionally not receiving new terminal passengers.

Reordering changes which waiting/loading jeepney is considered first for future assignment.

### 10.13 What Can Prevent It From Working

Terminal queue behavior can fail or be unavailable when:

- Route has terminal support disabled.
- No terminal location or fallback stop exists.
- Driver has no assigned jeepney.
- Trip is not in terminal queue mode.
- Trip is completed or cancelled.
- Admin session is invalid.
- Queue number conflict or stale data requires refresh.

### 10.14 How To Verify

1. Configure a route terminal.
2. Start a terminal queue trip.
3. Open admin dashboard.
4. Confirm the jeepney appears in the terminal dispatch board.
5. Move the jeepney up or down.
6. Confirm the order changes.
7. Skip the jeepney.
8. Confirm it remains visible but is marked skipped.
9. Create a terminal passenger request.
10. Confirm skipped jeepney is not selected for new assignment.
11. Restore the jeepney.
12. Confirm it returns to active queue handling.

More detail: [TERMINAL_QUEUE_MANAGEMENT.md](TERMINAL_QUEUE_MANAGEMENT.md).

## 11. Driver Process

### 11.1 Driver Login

Driver opens the driver app and logs in.

The app checks:

- Stored session if available.
- User role is driver.
- Backend can validate the session.

If the account is not a driver account, the driver app should block access.

### 11.2 Driver Profile And Assignments

Driver operations depend on:

- Driver profile.
- Assigned jeepney.
- Assigned route when required.
- Verification/status.

Without correct assignment, the driver may not be able to start valid trips or receive correct requests.

### 11.3 Going Online And Offline

Going online means the driver is available for operations. The app can align driver availability with session/app lifecycle and connectivity.

Going offline means the driver should not be treated as actively available.

### 11.4 Starting A Trip

A trip session represents one operating jeepney run.

Trip start requires:

- Driver authorization.
- Jeepney availability.
- Route reference.
- Valid route path.
- Driver/jeepney assignment rules.
- Trip not already completed or cancelled.

Backend result:

- Trip status becomes active.
- Start time is stored.
- Trip can accept requests if enabled.
- Driver can begin location sharing and request handling.

### 11.5 Route Mode

Route mode is normal route operation.

In route mode:

- Driver runs along a route.
- Passengers can create roadside pickup requests.
- Assignment can consider active route trips.
- Driver receives and acknowledges requests.

### 11.6 Terminal Queue Mode

Terminal queue mode is terminal-based dispatch.

In terminal queue mode:

- Driver/jeepney enters terminal queue.
- Queue number and terminal status matter.
- Terminal passenger requests are assigned through terminal queue rules.
- Admin can reorder, skip, and restore queue entries.

### 11.7 Location Sharing

Driver location sharing is important for:

- Passenger map updates.
- Admin operations visibility.
- Automatic onboarding.
- Automatic offboarding.
- Destination approach checks.
- Pass-by reassignment checks.

When driver sends location:

1. Backend validates driver session.
2. Backend stores or uses current location.
3. Backend can broadcast location to passengers/admins.
4. Backend can evaluate automatic onboarding for nearby acknowledged passengers.
5. Backend can evaluate automatic offboarding for onboard passengers who have separated.

### 11.8 Receiving Pickup Requests

Drivers receive pickup requests for their active trip.

Pickup request visibility depends on:

- Trip status.
- Trip ownership.
- Request status.
- Passenger assignment.
- Route/terminal logic.

### 11.9 Acknowledging Requests

Driver acknowledgment means the driver accepts or confirms the passenger request.

Backend result:

- Pickup request status becomes acknowledged.
- Passenger can proceed toward boarding.
- Automatic onboarding can begin watching proximity.
- Manual boarding validation can be used.

### 11.10 Manual Boarding

Manual boarding is a fallback and explicit action path.

It is used when:

- GPS is not reliable.
- Passenger wants to confirm directly.
- Automatic onboarding has not completed yet.
- Staff/driver flow needs explicit validation.

Manual boarding still updates the same ride and passenger count state as automatic onboarding.

### 11.11 Viewing Passenger Count

Driver passenger count is based on trip occupancy.

It increases when:

- Manual boarding completes.
- Automatic onboarding completes.

It decreases when:

- Manual ride completion/unload completes.
- Automatic offboarding completes.

### 11.12 Stop Alert Handling

When a passenger sends a stop alert, the driver can see and acknowledge it.

The alert is tied to:

- Passenger.
- Ride session.
- Trip.
- Destination/unload context.

When the ride completes, active stop alerts for that ride are dismissed.

### 11.13 Ending A Trip

Ending a trip marks the trip complete or no longer active.

Expected effects:

- Trip should stop accepting new requests.
- Driver operation for that trip ends.
- Terminal queue state should no longer be active.
- Remaining ride/request state must be handled according to backend rules.

### 11.14 Driver Support

Drivers can open support from the driver app for:

- Complaints.
- Lost items.
- Fare concerns.
- Trip issues.
- Safety concerns.
- General help.

A thread may include the current trip or route context. The driver can send multiple text messages, read admin replies, close the thread, and reopen it when more assistance is needed.

Support updates arrive through `support.*` socket events when available. The screen also refreshes every 30 seconds, coalesces overlapping refreshes, and ignores stale responses.

### 11.15 Driver Announcements

The driver app shows active driver-targeted announcements:

- The newest active announcement on the home view.
- All active announcements before ordinary notifications in the notifications area.
- Teal/neutral styling for info, amber for warning, and red for critical.

Dismissal applies only to the revision the driver saw. A stale revision response triggers an immediate refetch instead of hiding updated content.

## 12. Passenger Process

### 12.1 Passenger Registration And Login

Passenger can register or log in through the passenger app.

The app checks:

- Stored session.
- Passenger role.
- Backend user status.

If the account is not a passenger account, the passenger app should block access.

### 12.2 Route Browsing

Passenger can browse available routes.

Route browsing depends on:

- Backend route list.
- Active route status.
- Route geometry.
- Stops/landmarks for display and booking.

### 12.3 Trip Selection

Passenger may select an active trip or allow the backend to choose an eligible trip.

Trip selection depends on:

- Route.
- Active trip availability.
- Request acceptance.
- Capacity.
- Terminal queue rules if terminal booking.

### 12.4 Roadside Booking

Roadside booking is used when the passenger wants pickup along the route.

It requires:

- Passenger location.
- Pickup point near route.
- Pickup point near passenger current location.
- Destination/unload point on or near route.
- Destination after pickup along route progression.
- Eligible trip.

Backend result:

- Pickup request is created.
- Request starts as pending unless immediately acknowledged by flow.
- Driver/trip receives request context.

### 12.5 Terminal Booking

Terminal booking is used when the passenger boards from the terminal.

It requires:

- Route terminal support.
- Terminal location or fallback terminal stop.
- Destination/unload selection.
- Eligible terminal queue trip.
- Non-skipped terminal queue jeepney.

Backend result:

- Pickup request uses terminal pickup type.
- Pickup location is the terminal.
- Assignment follows terminal queue logic.

### 12.6 Pickup Pin And Destination Pin

Passenger selects:

- Pickup point for roadside booking.
- Destination/unload point for both roadside and terminal booking.

The destination is important because:

- Fare can be calculated.
- Stop alerts have a target context.
- Manual unload validation can compare against destination/route.
- Destination approach alerts can be triggered.

### 12.6.1 Live Jeep Plate And Traffic ETA

Passengers can tap a visible jeepney marker to view:

- Plate number.
- Google traffic-aware ETA to the selected pickup pin, or current GPS location when no pickup pin exists.
- Remaining road distance.
- Available seats.
- Vehicle location freshness.

The backend owns the ETA origin and resolves it from the active trip's authoritative jeepney location. It rejects inactive trips, invalid destinations, vehicle locations older than 60 seconds, and boarding points the jeepney has already passed.

The jeep and destination are projected onto the trip route snapshot. The remaining route is sampled into Google via-points so the result follows the assigned jeepney route instead of proposing a shortcut or U-turn. Google is called with `TRAFFIC_AWARE_OPTIMAL`.

The passenger app refreshes the selected jeep ETA:

- Immediately after marker selection.
- Every 30 seconds while the jeep remains selected.
- After at least 100 meters of realtime movement when the previous request is at least 10 seconds old.

Identical trip/destination calculations are rounded to approximately 10 meters, cached, and coalesced for 25 seconds by the backend. ETA is unavailable when Google routing is unavailable, the vehicle location is stale, or the jeepney has already passed the pickup point; no average-speed fallback is shown.

### 12.7 Request Submission

When passenger submits a request:

1. App sends route/trip/pickup/destination data to backend.
2. Backend validates passenger identity.
3. Backend validates route and trip.
4. Backend validates pickup and destination geometry.
5. Backend checks duplicate/pending request limits.
6. Backend checks trip capacity and availability.
7. Backend creates pickup request.
8. Backend returns request data to passenger app.

### 12.8 Request Status

Passenger request status tells the passenger what is happening:

- Pending: waiting for driver/assignment handling.
- Acknowledged: driver accepted or confirmed the request.
- Completed: boarding happened and the request is fulfilled.
- Cancelled: passenger or system cancelled it.
- Expired: request timed out or became invalid.

### 12.9 Waiting For Driver Acknowledgment

Automatic onboarding should only happen after acknowledgment. This prevents the system from marking someone onboard just because they are near a jeepney before the driver accepts the request.

### 12.10 Boarding

Passenger can become onboard through:

- Manual boarding validation.
- Automatic onboarding by proximity dwell.

Both paths should result in ride state and passenger count updates.

### 12.11 Ride Monitoring

After boarding:

- Passenger sees active/onboard ride state.
- Passenger can watch driver/trip context.
- Passenger can send digital para/stop alert if allowed.
- Passenger can manually unload if automatic offboarding does not complete.

### 12.12 Digital Para / Stop Alert

Passenger can send a stop alert only when the ride is verified onboard and stop alerts are allowed.

### 12.13 Manual Unload

Manual unload lets the passenger close the ride explicitly.

It is important as a fallback when:

- GPS is unavailable.
- Internet is unstable.
- Passenger and driver locations are stale.
- Automatic offboarding has not met its separation rules.

### 12.14 Ride Completion

Ride completion changes the ride session to completed and decreases trip occupancy.

Completion can be:

- Manual.
- Automatic by separation.

### 12.15 Passenger Support

Passengers can create a two-way admin support thread for complaints or help. Optional booking and ride context can include the passenger-owned pickup request, ride session, trip session, or route.

The passenger can:

- Create a categorized thread.
- Send and receive multiple text messages.
- See unread and status changes.
- Close or reopen the conversation.

The support list and detail screen use realtime updates, 30-second polling fallback, request coalescing, and generation guards. A failed support refresh does not stop booking, maps, ride tracking, or other dashboard operations.

### 12.16 Passenger Announcements

The passenger app shows active passenger-targeted announcements:

- The newest active card on the main home view.
- All active cards before ordinary notices.
- Category, title, complete or compact body, relative publication time, optional expiry, and severity styling.

Announcement loading is best-effort and does not participate in the blocking dashboard `Future.wait`. The app keeps the last successful snapshot when possible and shows no blocking announcement error on first-load failure.

## 13. Pickup Request Lifecycle

### 13.1 Pending

Pending means the request has been created but not yet acknowledged or completed.

Created by:

- Passenger submitting a valid pickup request.

User sees:

- Passenger waits.
- Driver/admin may see the request depending on flow.

Backend stores:

- Pickup request with status `pending`.
- Pickup and destination information.
- Passenger/trip/route references.
- Expiry time.

### 13.2 Acknowledged

Acknowledged means the driver has accepted or confirmed the request.

Created by:

- Driver acknowledgment endpoint/action.

User sees:

- Passenger is told to prepare or board.
- Driver sees request as accepted/active.

Backend stores:

- Pickup request status `acknowledged`.
- Acknowledgment metadata where applicable.
- Auto-boarding can begin from this point.

### 13.3 Completed

Completed means the pickup request has been fulfilled by boarding.

Created by:

- Manual boarding validation.
- Automatic onboarding.

User sees:

- Passenger is onboard.
- Driver passenger count increases.

Backend stores:

- Pickup request status `completed`.
- Ride session onboard state.
- Trip occupancy increase.

### 13.4 Cancelled

Cancelled means the request was stopped before boarding.

Created by:

- Passenger cancellation.
- Possible admin/system action depending on route.

User sees:

- Request is no longer active.

Backend stores:

- Pickup request status `cancelled`.

### 13.5 Expired

Expired means the request became too old or invalid before completion.

Created by:

- TTL expiry.
- Pass-by reassignment/expiration logic.
- Operational cleanup rules.

User sees:

- Request is no longer active.
- Passenger may need to create a new request.

Backend stores:

- Pickup request status `expired`.

### 13.6 TTL Behavior

Pickup requests have a time-to-live behavior controlled by configuration.

Default:

```env
PICKUP_REQUEST_TTL_MINUTES=12
```

The request should not stay pending forever. Expiry protects drivers, passengers, and assignment logic from stale requests.

### 13.7 Duplicate/Pending Request Limits

The backend limits repeated pending requests per passenger/trip.

Default:

```env
MAX_REQUESTS_PER_PASSENGER_PER_TRIP=2
```

This prevents one passenger from flooding the same trip with multiple active requests.

## 14. Automatic Assignment And Reassignment

### 14.1 What Assignment Does

Assignment chooses which trip/jeepney should receive a passenger request.

It considers:

- Route.
- Trip status.
- Request acceptance.
- Capacity.
- Operating mode.
- Terminal queue state for terminal booking.
- Passenger pickup type.

### 14.2 Active Trip Selection

For normal route operations, the backend can select an eligible active trip.

Eligible trips should generally:

- Be active.
- Match the selected route.
- Accept requests.
- Have available capacity.
- Be valid for the passenger pickup context.

### 14.3 Terminal Queue Trip Selection

For terminal bookings, the backend should select from terminal queue trips.

Eligible terminal trips should generally:

- Match the route.
- Be in terminal queue mode.
- Be waiting or loading.
- Not be skipped.
- Have capacity.
- Be ordered by queue rules.

### 14.4 Skipped Trips Are Ignored

Skipped terminal trips remain visible to admins but are ignored for new terminal passenger assignment.

This allows staff to keep operational visibility without accidentally assigning passengers to a jeepney that was intentionally skipped.

### 14.5 Pass-By Reassignment

Automatic reassignment handles cases where a jeepney passes the passenger without completing pickup.

Default pass-by threshold:

```env
JEEP_PASS_BY_REASSIGN_METERS=50
```

The purpose is to avoid leaving passengers stuck on a request tied to a jeepney that already passed them.

Possible result:

- Request is reassigned to another eligible jeepney.
- Request expires if no replacement is available.
- Passenger receives updated status/notification.

More detail: [AUTOMATIC_REASSIGNMENT.md](AUTOMATIC_REASSIGNMENT.md).

### 14.6 What Happens When Jeepney Is Full

If the jeepney is full:

- It should not receive new passengers.
- Existing requests may need reassignment or rejection depending on state.
- Admin/driver views should reflect occupancy.

### 14.7 What Happens When No Eligible Jeepney Exists

If no eligible trip exists:

- The request may fail creation.
- The passenger may be told no jeepney is available.
- A pending request may expire later depending on flow.
- Manual operational intervention may be needed.

## 15. Manual Boarding

### 15.1 What Manual Boarding Means

Manual boarding is the explicit flow where passenger or driver action validates that the passenger boarded.

It is the fallback and confirmation path when automatic onboarding cannot safely decide.

### 15.2 Conditions Required

Manual boarding generally requires:

- Valid passenger session.
- Existing pickup request.
- Request assigned to a trip.
- Driver has acknowledged the request.
- Trip is valid and active.
- Boarding time/location rules are satisfied.
- Destination/unload point exists where required.

### 15.3 Driver Acknowledgment Requirement

Driver acknowledgment protects against accidental boarding.

The system should not treat a passenger as boarded before the driver accepts the pickup request.

### 15.4 Boarding Validation Endpoint

Manual boarding uses boarding validation through the backend.

Backend result:

- Validates trip/request/passenger context.
- Creates or updates ride session.
- Marks ride onboard.
- Marks pickup request completed.
- Increases trip occupancy.
- Enables stop alert capability when appropriate.
- Notifies driver/passenger as needed.

### 15.5 Ride Session Creation

Manual boarding creates the ride state that connects:

- Passenger.
- Trip.
- Pickup request.
- Pickup type.
- Boarding location.
- Destination/unload location.
- Fare snapshot.

### 15.6 Passenger Count Increase

Manual boarding increases the trip passenger count.

This count is what driver/admin views use to understand onboard occupancy.

### 15.7 Terminal Queue Refresh After Boarding

If the pickup is terminal-based, boarding can affect terminal queue state.

For example:

- A queue trip with terminal passengers may remain loading.
- Queue state can be synchronized after request/boarding changes.

## 16. Automatic Onboarding

### 16.1 What Automatic Onboarding Means

Automatic onboarding marks a passenger as onboard without requiring manual tap confirmation, but only after the system has enough evidence that the passenger is with the driver/jeepney.

The rule requested for ParaGO is:

If the passenger is with the driver for more than 10 seconds, consider the passenger onboard.

### 16.2 Who Uses It

Passengers benefit because boarding can happen naturally.

Drivers benefit because the passenger count updates without extra manual work.

Admins benefit because the live operational state becomes more accurate.

### 16.3 What Must Exist Before It Works

Automatic onboarding requires:

- Passenger has an acknowledged pickup request.
- Trip is active.
- Driver/jeepney location is recent.
- Passenger location is recent.
- Passenger is near the driver/jeepney.
- Passenger stays near long enough.
- Backend automation service is triggered by location updates.

### 16.4 Default Configuration

```env
AUTO_BOARDING_PROXIMITY_METERS=25
AUTO_BOARDING_DWELL_SECONDS=10
AUTO_BOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_BOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

Meaning:

- Passenger must be within 25 meters by default.
- Passenger must stay within range for 10 seconds by default.
- Passenger location older than 45 seconds is stale.
- Driver location older than 20 seconds is stale.

### 16.5 Location Inputs

Passenger app sends passenger location to:

```http
POST /passengers/me/location
PATCH /passengers/me/location
PUT /passengers/me/location
```

Driver app sends driver location through driver location endpoints such as:

```http
PATCH /drivers/me/location
PATCH /drivers/location
```

When either side reports location, the backend can reevaluate automation.

### 16.6 Step-By-Step Process

1. Passenger creates a pickup request.
2. Driver acknowledges the request.
3. Passenger app reports passenger location.
4. Driver app reports jeepney/driver location.
5. Backend checks whether both locations are recent.
6. Backend calculates passenger-to-driver distance.
7. If distance is within the configured proximity, backend starts or continues the dwell timer.
8. If passenger stays within proximity for at least the dwell duration, backend completes boarding.
9. Backend creates or updates the ride session.
10. Backend marks pickup request completed.
11. Backend increases trip occupancy.
12. Backend notifies driver/passenger as needed.

### 16.7 Timer And Reset Behavior

The 10-second rule is not simply one location ping.

The passenger must remain close long enough. If the passenger moves too far before the dwell time is complete, the proximity timer resets.

This prevents accidental onboarding when:

- Passenger briefly passes near the jeepney.
- GPS briefly jumps near the jeepney.
- The driver passes the passenger without actual boarding.

### 16.8 Backend State Changes

When automatic onboarding completes:

- `PickupRequest.status` becomes `completed`.
- `RideSession.status` becomes `onboard`.
- `RideSession.boardingMethod` becomes `auto_proximity`.
- `RideSession.boardedAt` is set.
- `TripSession.occupancyCount` increases by 1.
- Terminal queue state may be synchronized for terminal pickups.

### 16.9 User-Facing Result

Passenger should see:

- Ride changes to onboard.
- Manual boarding prompt is no longer needed.
- Stop alert may become available when allowed.

Driver should see:

- Passenger count increases.
- Passenger is considered onboard.
- Notification/status update may appear.

Admin should see:

- Trip/ride state reflects onboard passenger.
- Reports and dashboard data can include the boarded ride.

### 16.10 Fallback Behavior

Manual boarding remains available.

Automatic onboarding does not complete when:

- Passenger GPS is stale.
- Driver GPS is stale.
- Network prevents location updates.
- Passenger is outside proximity.
- Pickup request is not acknowledged.
- Trip is not active.

This is intentional. Stale or uncertain GPS should not increase passenger count.

### 16.11 How To Verify

1. Start driver trip.
2. Passenger creates pickup request.
3. Driver acknowledges request.
4. Put passenger and driver devices near each other.
5. Wait more than 10 seconds.
6. Confirm passenger becomes onboard.
7. Confirm driver passenger count increases.
8. Move away before 10 seconds in another test.
9. Confirm onboarding does not complete.
10. Disable GPS/network in another test.
11. Confirm manual boarding still works.

More detail: [AUTOMATIC_ONBOARDING.md](AUTOMATIC_ONBOARDING.md).

## 17. Ride Session Lifecycle

### 17.1 What A Ride Session Represents

A ride session is the passenger's actual ride record.

It connects:

- Passenger.
- Trip.
- Pickup request.
- Route context.
- Pickup type.
- Boarding location.
- Destination/unload location.
- Fare snapshot.
- Boarding method.
- Offboarding method.

### 17.2 Waiting Ride

`waiting` means the ride exists but is not fully onboard yet.

This state may be used for transition flows where request and ride data exist before final onboard confirmation.

### 17.3 Onboard Ride

`onboard` means the passenger is currently considered inside the jeepney.

Effects:

- Passenger count should include this passenger.
- Stop alert may be allowed.
- Automatic offboarding can monitor separation.
- Manual unload can be used.

### 17.4 Completed Ride

`completed` means the ride has ended.

Effects:

- Passenger count should no longer include this passenger.
- Active stop alerts for the ride are dismissed.
- Ride is no longer eligible for onboard controls.
- Reports can include it as a completed ride.

### 17.5 Boarding Method

`boardingMethod` explains how the passenger became onboard.

Values:

- `manual`: boarding was manually validated.
- `auto_proximity`: automatic onboarding completed after proximity dwell.

### 17.6 Offboarding Method

`offboardingMethod` explains how the ride completed.

Values:

- `manual`: passenger/driver completed the ride manually.
- `auto_separation`: automatic offboarding completed after separation checks.

### 17.7 How Ride State Affects Controls

Passenger controls depend on ride state:

- Before onboard: passenger may wait or board.
- Onboard: passenger may send stop alert and unload.
- Completed: passenger should not send active ride controls for that ride.

Driver controls depend on ride state:

- Acknowledged request can be boarded.
- Onboard passenger contributes to count.
- Completed passenger no longer contributes to count.

## 18. Automatic Offboarding

### 18.1 What Automatic Offboarding Means

Automatic offboarding marks a passenger as unloaded when the passenger and driver/jeepney become too far apart for long enough.

The requested behavior is:

When the passenger and driver become too far from one another, consider the passenger offboard, but include fallback because internet problems can happen.

### 18.2 Who Uses It

Passengers benefit because the ride can close automatically after they leave the jeepney.

Drivers benefit because passenger count decreases without needing manual action.

Admins benefit because occupancy and reports become more accurate.

### 18.3 What Must Exist Before It Works

Automatic offboarding requires:

- Existing ride session.
- Ride status is `onboard`.
- Trip is active.
- Passenger location is recent.
- Driver/jeepney location is recent.
- Passenger is outside the configured separation distance.
- Separation is confirmed repeatedly or sustained long enough.

### 18.4 Default Configuration

```env
AUTO_OFFBOARDING_DISTANCE_METERS=120
AUTO_OFFBOARDING_CONSECUTIVE_OUTSIDE_CHECKS=3
AUTO_OFFBOARDING_SUSTAINED_SEPARATION_SECONDS=60
AUTO_OFFBOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_OFFBOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

Meaning:

- Passenger must be more than 120 meters away by default.
- Separation must be confirmed for 3 outside checks or 60 sustained seconds.
- Passenger location older than 45 seconds is stale.
- Driver location older than 20 seconds is stale.

### 18.5 Why It Uses Repeated Checks

The system should not complete a ride because of one bad GPS point.

Repeated checks and sustained separation protect against:

- GPS jumps.
- Slow network updates.
- Temporary location inaccuracy.
- Passenger phone briefly reporting wrong location.
- Driver phone briefly reporting wrong location.

### 18.6 Step-By-Step Process

1. Passenger is onboard.
2. Passenger app reports location.
3. Driver app reports location.
4. Backend checks both locations are recent.
5. Backend calculates passenger-to-driver distance.
6. If distance is inside range, separation state resets.
7. If distance is outside range, backend records outside check state.
8. If outside checks reach the required count or sustained separation time is reached, backend completes the ride.
9. Backend marks ride completed.
10. Backend decreases trip occupancy.
11. Backend dismisses active stop alerts for the ride.
12. Backend notifies passenger and driver as needed.

### 18.7 Backend State Changes

When automatic offboarding completes:

- `RideSession.status` becomes `completed`.
- `RideSession.offboardingMethod` becomes `auto_separation`.
- `RideSession.endedAt` is set.
- `TripSession.occupancyCount` decreases by 1.
- Active stop alerts for the ride are dismissed.
- Notifications may be created for passenger and driver.

### 18.8 Reset Behavior

If passenger returns near the jeepney before separation completes:

- Separation timer resets.
- Outside count resets.
- Ride remains onboard.
- Passenger count stays unchanged.

This protects the system from ending rides too early.

### 18.9 Network And GPS Fallback

Automatic offboarding pauses or does not complete when:

- Passenger location is stale.
- Driver location is stale.
- Internet prevents new location updates.
- GPS permission is disabled.
- Distance cannot be calculated safely.

Manual unload remains available so the passenger can still complete the ride.

### 18.10 User-Facing Result

Passenger should see:

- Ride becomes completed after confirmed separation.
- Manual unload is still available if automation does not complete.

Driver should see:

- Passenger count decreases.
- Passenger is no longer onboard.

Admin should see:

- Ride and occupancy state update in dashboards/reports.

### 18.11 How To Verify

1. Complete boarding so passenger is onboard.
2. Confirm driver passenger count increased.
3. Move passenger and driver apart beyond configured separation distance.
4. Keep both apps sending location updates.
5. Wait until repeated/sustained separation rule completes.
6. Confirm ride becomes completed.
7. Confirm driver passenger count decreases.
8. Test returning near the driver before completion.
9. Confirm offboarding resets and ride stays onboard.
10. Disable internet/GPS.
11. Confirm manual unload remains usable.

More detail: [AUTOMATIC_OFFBOARDING.md](AUTOMATIC_OFFBOARDING.md).

## 19. Passenger Count Behavior

### 19.1 Where Passenger Count Is Stored

Passenger count is stored on the trip session as occupancy count.

Important fields:

- `occupancyCount`: current onboard passenger count.
- `manualOccupancyCount`: manual count support where used.

### 19.2 What Increases Passenger Count

Passenger count increases when a passenger becomes onboard.

This can happen through:

- Manual boarding validation.
- Automatic onboarding by proximity dwell.

### 19.3 What Decreases Passenger Count

Passenger count decreases when a ride completes.

This can happen through:

- Manual unload/ride completion.
- Automatic offboarding by separation.

### 19.4 Manual Boarding Effect

Manual boarding:

- Creates or updates ride session.
- Sets ride onboard.
- Marks pickup request completed.
- Increases occupancy count.

### 19.5 Automatic Onboarding Effect

Automatic onboarding:

- Uses proximity and dwell time.
- Sets `boardingMethod = auto_proximity`.
- Increases occupancy count.

### 19.6 Manual Unload Effect

Manual unload:

- Completes ride.
- Sets or uses manual offboarding method.
- Decreases occupancy count.
- Dismisses active stop alerts.

### 19.7 Automatic Offboarding Effect

Automatic offboarding:

- Uses repeated/sustained separation.
- Sets `offboardingMethod = auto_separation`.
- Decreases occupancy count.
- Dismisses active stop alerts.

### 19.8 Why Stale GPS Should Not Change Count

Stale GPS should not increase or decrease passenger count because the system cannot safely know where the passenger or jeepney is.

This avoids:

- False onboard status.
- False ride completion.
- Incorrect driver passenger count.
- Incorrect admin reports.

### 19.9 How Driver And Admin Views Are Affected

Driver view:

- Passenger count updates after boarding/offboarding.
- Driver can understand current onboard load.

Admin view:

- Dashboard and reports can reflect current operational state.
- Terminal queue and trip monitoring become more accurate.

## 20. Stop Alert / Digital Para

### 20.1 What It Is

The digital para is a stop alert sent by the passenger while onboard.

It replaces or supports the real-world action of telling the driver where the passenger wants to unload.

### 20.2 When Passenger Can Send It

Passenger can send a stop alert only when:

- Passenger has an onboard ride.
- Ride allows stop alerts.
- Destination/unload context is available.
- Cooldown rules allow it.

### 20.3 Required Onboard Ride State

Stop alerts require verified onboard state so passengers do not send unload alerts before riding.

### 20.4 Destination/Unload Point Behavior

The alert is tied to the passenger's destination/unload point.

This lets the driver see where the passenger intends to unload and lets the backend connect the alert to the ride session.

### 20.5 Cooldown

Stop alert cooldown prevents repeated alert spam.

Default:

```env
STOP_ALERT_COOLDOWN_MINUTES=2
```

### 20.6 Driver Acknowledgment

Driver can acknowledge the alert.

The alert status can move through states such as sent, seen, acknowledged, or dismissed.

### 20.7 Automatic Dismissal

When the ride completes, active stop alerts for that ride are dismissed.

This keeps old alerts from staying active after the passenger has already unloaded.

## 21. Notifications And Realtime

### 21.1 Notification Creation

Notifications are created for important events such as:

- Request updates.
- Driver acknowledgment.
- Boarding completion.
- Ride completion.
- Stop alerts.
- Reassignment events.

### 21.2 User-Specific Notifications

Notifications are scoped to the user who needs them.

Examples:

- Passenger receives ride status changes.
- Driver receives passenger/request events.
- Admin sees operational activity through dashboard and logs.

### 21.3 Admin Operations Events

Admin operations events allow dashboards to react to operational changes.

These can include:

- New requests.
- Boarding events.
- Ride completions.
- Queue changes.
- Driver/trip updates.

### 21.4 Optional Socket.IO Realtime

Realtime is optional.

When enabled:

- The backend authenticates the socket using the user's access token.
- Every socket joins `user:<userId>` and `role:<role>` rooms.
- Clients can subscribe to route and trip rooms where needed.
- Passenger maps can update quickly.
- Admin dashboard can refresh faster.
- Support and announcement views can reconcile immediately.

Important events include:

- `notification.created`
- `ops.changed`
- `jeepney.location.updated`
- `support.thread.created`
- `support.message.created`
- `support.thread.updated`
- `support.thread.read`
- `announcement.published`
- `announcement.updated`
- `announcement.archived`

Support event payloads include both the event name and canonical `threadId`. The Flutter clients also accept older payloads where the thread identifier was returned as `id` or `_id`.

When the backend emits `socket.ready`, support and announcement clients refetch their API state. A network failure does not erase route/trip subscription intent. Clients retry the same socket after 15 seconds and restore route/trip subscriptions after connection.

### 21.5 Polling Fallback

When realtime is disabled or unavailable:

- Apps continue to use API refresh loops.
- Users may see updates with slight delay.
- Core operations still work through REST endpoints.
- Support lists and open thread details refresh silently every 30 seconds.
- Announcement feeds reconcile on their existing 30-second refresh cycle.
- Overlapping support refreshes are coalesced and one pending refresh is retained.

### 21.6 Driver Location Broadcast

Driver location updates can be broadcast to:

- Passengers watching the route.
- Passengers connected to the trip.
- Admin operational views.

Location updates also trigger backend automation checks.

### 21.7 Passenger Map Updates

Passenger app can show jeepney movement using realtime updates or polling fallback.

This depends on:

- Driver app sending location.
- Backend accepting location.
- Passenger app having selected route/trip context.
- Realtime or refresh loop receiving updated data.

More detail: [REALTIME_COMPLETE.md](REALTIME_COMPLETE.md).

### 21.8 Service Announcements

Admins can publish or schedule service changes, disruptions, maintenance,
safety notices, and general updates for passengers, drivers, or both.

Announcements are stored once and delivered through role-based API queries and
Socket.IO refresh events. They do not create per-user notification rows or
change ordinary notification unread counts.

Users can dismiss the current announcement revision. Dismissals persist for
that account across devices, while a published edit increments the revision
and makes the updated announcement visible again.

Scheduled and expired states are reconciled every 30 seconds, and active
queries also enforce start and expiry times directly.

Lifecycle transitions use atomic conditional updates so multiple backend instances cannot publish or expire the same record twice. Admin edits to expired or archived records are rejected.

Dismiss requests must include the revision shown to the user:

```json
{
  "revision": 3
}
```

If the revision is stale, the backend returns `409` with the current revision. The client removes the old optimistic card and refetches instead of restoring content that has already been superseded.

Announcement loading remains independent from core passenger and driver dashboard loading. Endpoint failure keeps the last successful snapshot or uses an empty first-load result without showing a blocking error.

### 21.9 Support Chat Realtime

Support chat is passenger-to-admin and driver-to-admin only. It is not a general user-to-user chat system.

The normal flow is:

1. Passenger or driver creates a thread with category, subject, initial message, and optional operational context.
2. Backend validates ownership and stores the thread and first message.
3. Admin role sockets and the owner socket receive `support.thread.created`.
4. Either side sends another message.
5. Backend updates last-message, unread, and lifecycle fields.
6. Both sides receive `support.message.created` and refetch the thread.
7. Read, assignment, resolution, close, and reopen actions emit thread updates.

Direct support socket payloads and `ops.changed` use the same canonical thread identifier. User-specific durable notifications may still be generated for support replies, but the support conversation itself is stored in `SupportThread` and `SupportMessage`.

### 21.10 Client Cache And Race Protection

The three Flutter clients use an API cache for selected GET requests:

- Routes: up to 6 hours.
- Active/mine trips: 8 seconds.
- Notifications: 20 seconds.
- Pickup, ride, and stop-alert views: 10 seconds.
- Other cache-enabled GET requests: 30 seconds by default.

Concurrent identical GET requests are coalesced. An expired cached response may be used as a network-failure fallback when that request opted into caching.

Mutation behavior is intentionally split:

- Support mutations invalidate only support cache entries.
- Announcement mutations invalidate only announcement entries.
- Notification mutations invalidate only notification entries.
- Cross-domain operations such as trips and bookings clear the broader cache.

Every successful mutation increments a cache generation. A GET that started before that mutation may still return to its caller, but it cannot write its older response back into the cache.

Logout clears all memory and persisted API cache entries before another account can use the app.

## 22. Reports And Monitoring

### 22.1 Request Reports

Request reports show pickup request activity.

They help answer:

- How many passengers requested rides?
- Which requests were completed?
- Which expired or were cancelled?
- Which routes have high demand?

### 22.2 Boarding Reports

Boarding reports show boarding activity.

They help answer:

- How many passengers boarded?
- Which trips had boardings?
- How much boarding used manual vs automatic behavior where tracked?

### 22.3 Alert Reports

Alert reports show stop alert activity.

They help answer:

- How many digital para alerts were sent?
- Which trips/routes had many alerts?
- Whether alerts were acknowledged or dismissed.

### 22.4 Trip Activity Reports

Trip activity reports show driver/jeepney trip operations.

They help answer:

- How many trips ran?
- Which routes were active?
- Which drivers/jeepneys operated?
- Trip start/end patterns.

### 22.5 Route Demand Reports

Route demand reports show which routes passengers use most.

They help support:

- Dispatch planning.
- Route improvements.
- Driver allocation.
- Terminal staffing decisions.

### 22.6 Passenger Flow Reports

Passenger flow reports show movement patterns across boarding and unload points.

They help answer:

- Where passengers board.
- Where passengers unload.
- Which segments have demand.

## 23. API Capability Reference

This section lists the main API groups and the capability each group supports. Exact endpoint details should be checked in the backend route files when implementing client changes.

### 23.1 Auth

API group:

```http
/auth
```

Capabilities:

- Email registration.
- Email login.
- Social login.
- Firebase Google login.
- Admin OTP login flow.
- Current user lookup.
- Token refresh.
- Logout.

### 23.2 Users

API group:

```http
/users
```

Capabilities:

- User profile access.
- User update operations.
- User administration where authorized.

### 23.3 Passengers

API group:

```http
/passengers
```

Capabilities:

- Passenger profile access.
- Passenger profile update.
- Passenger location update for ride automation.

Important automation endpoint:

```http
/passengers/me/location
```

### 23.4 Drivers

API group:

```http
/drivers
```

Capabilities:

- Driver profile access.
- Driver status updates.
- Driver location updates.
- Driver trip/request context.
- Automatic boarding/offboarding trigger from driver location.

### 23.5 Admin

API group:

```http
/admin
```

Capabilities:

- Dashboard metrics.
- Recent activity.
- Driver management.
- Jeepney assignment.
- Hybrid dispatch board.
- Terminal queue reorder.
- Terminal queue skip/restore.
- Route preview helpers.

Important terminal queue endpoints:

```http
GET /admin/hybrid-dispatch
PATCH /admin/terminal-queue/:tripId/reorder
PATCH /admin/terminal-queue/:tripId/skip
```

### 23.6 Jeepneys

API group:

```http
/jeepneys
```

Capabilities:

- Jeepney list.
- Jeepney create.
- Jeepney update.
- Jeepney deactivate/delete behavior depending on route implementation.
- Jeepney assignment support.

### 23.7 Routes

API group:

```http
/routes
```

Capabilities:

- Route list.
- Route create.
- Route update.
- Route deactivate/delete.
- Route geometry storage.
- Landmark/stop storage.
- Fare configuration.
- Terminal settings update through route payload.

Admin route preview routing supports normalized navigation sources:

- `google`
- `tomtom`
- `openstreetmap`
- `cached`

When `GOOGLE_ROUTES_API_KEY` is configured, route preview tries Google traffic-aware routing first. Google results populate existing `durationSeconds`, `rawDurationSeconds`, and `trafficDelayInSeconds` fields. Server-side Google failures fall back to TomTom when `TOMTOM_API_KEY` is configured. Existing OSM/OSRM client route generation remains a separate compatibility path. All clients continue to draw the returned geometry with `flutter_map`.

### 23.8 Trips

API group:

```http
/trips
```

Capabilities:

- Active trip listing.
- Driver trip listing.
- Trip creation.
- Trip start.
- Trip end.
- Availability/request acceptance update.
- Occupancy updates where supported.
- Passenger-only live traffic ETA through `POST /trips/:tripId/passenger-eta`.

The live ETA endpoint derives the origin from the active jeepney location, follows the trip route using pass-through waypoints, returns the authoritative plate number, and caches matching requests for 25 seconds. The Google API key remains server-side.

Response data includes:

```json
{
  "tripId": "...",
  "jeepneyId": "...",
  "plateNumber": "...",
  "distanceMeters": 0,
  "durationSeconds": 0,
  "rawDurationSeconds": 0,
  "trafficDelayInSeconds": 0,
  "source": "google",
  "vehicleLocationLastSeenAt": "...",
  "calculatedAt": "...",
  "expiresAt": "..."
}
```

### 23.9 Pickup Requests

API group:

```http
/pickup-requests
```

Capabilities:

- Create pickup request.
- List passenger requests.
- List trip requests.
- Acknowledge request.
- Complete request.
- Cancel request.
- Reverse-geocode support where implemented.
- Assignment/reassignment logic.

### 23.10 Boarding

API group:

```http
/boarding
```

Capabilities:

- Manual boarding validation.
- Passenger ride session listing through boarding context.

### 23.11 Ride Sessions

API group:

```http
/ride-sessions
```

Capabilities:

- Passenger ride list.
- Trip ride list.
- Ride completion.
- Manual unload behavior.
- Shared ride completion logic used by automatic offboarding.

### 23.12 Stop Alerts

API group:

```http
/stop-alerts
```

Capabilities:

- Create stop alert.
- List trip stop alerts.
- Acknowledge stop alert.

### 23.13 Notifications

API group:

```http
/notifications
```

Capabilities:

- List user notifications.
- Mark one notification read.
- Mark all notifications read.

### 23.14 Reports

API group:

```http
/reports
```

Capabilities:

- Request reports.
- Boarding reports.
- Alert reports.
- Trip activity reports.
- Route demand reports.
- Passenger flow reports.

### 23.15 Announcements

API group:

```http
/announcements
```

Passenger and driver endpoints:

```http
GET /announcements/active
POST /announcements/:id/dismiss
```

Admin endpoints:

```http
GET /announcements/admin
POST /announcements/admin
PATCH /announcements/admin/:id
POST /announcements/admin/:id/archive
```

Capabilities:

- Role-targeted active list.
- Revision-specific dismissal.
- Paginated and filtered admin history.
- Immediate or scheduled creation.
- Scheduled/published editing with revision increment.
- Atomic publish/expiry reconciliation.
- Critical-publication and active-archive confirmations.
- Archive without hard deletion.

### 23.16 Support

API group:

```http
/support
```

Passenger and driver endpoints:

```http
POST /support/threads
GET /support/threads
GET /support/threads/:id/messages
POST /support/threads/:id/messages
PATCH /support/threads/:id/read
PATCH /support/threads/:id/close
PATCH /support/threads/:id/reopen
```

Admin capabilities add:

- Shared inbox listing and filters.
- Assignment.
- Resolution.
- Access to passenger and driver threads.

Ownership rules prevent one passenger or driver from reading another user's support thread.

## 24. Runtime Configuration

### 24.1 Required Backend Configuration

```env
MONGO_URI=
JWT_SECRET=
```

`MONGO_URI` is required for database access.

`JWT_SECRET` is required for access token signing.

### 24.2 Auth And Session Configuration

```env
JWT_EXPIRES_IN=7d
JWT_REFRESH_SECRET=
JWT_REFRESH_EXPIRES_IN=30d
```

If `JWT_REFRESH_SECRET` is not set, the backend can fall back to `JWT_SECRET`.

In production, secrets must not use placeholder values.

### 24.3 Pickup And Boarding Configuration

```env
BOARDING_WINDOW_MINUTES=10
PICKUP_REQUEST_TTL_MINUTES=12
MAX_REQUESTS_PER_PASSENGER_PER_TRIP=2
PICKUP_ROAD_PROXIMITY_METERS=300
PICKUP_CURRENT_LOCATION_MAX_DISTANCE_METERS=50
```

These values control:

- Boarding time window.
- Request expiry.
- Duplicate request limits.
- Pickup distance from route.
- Pickup distance from passenger current location.

### 24.4 Stop Alert And Unload Configuration

```env
STOP_ALERT_COOLDOWN_MINUTES=2
STOP_ALERT_ROAD_PROXIMITY_METERS=300
UNLOAD_ROAD_PROXIMITY_METERS=5
DESTINATION_APPROACH_ALERT_METERS=50
```

These values control:

- Digital para cooldown.
- Stop alert location tolerance.
- Manual unload route proximity.
- Destination approach alerts.

### 24.5 Automatic Reassignment Configuration

```env
JEEP_PASS_BY_REASSIGN_METERS=50
```

This controls pass-by detection for reassignment.

### 24.6 Automatic Onboarding Configuration

```env
AUTO_BOARDING_PROXIMITY_METERS=25
AUTO_BOARDING_DWELL_SECONDS=10
AUTO_BOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_BOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

These values control how close and how long passenger/driver must be before automatic onboarding.

### 24.7 Automatic Offboarding Configuration

```env
AUTO_OFFBOARDING_DISTANCE_METERS=120
AUTO_OFFBOARDING_CONSECUTIVE_OUTSIDE_CHECKS=3
AUTO_OFFBOARDING_SUSTAINED_SEPARATION_SECONDS=60
AUTO_OFFBOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_OFFBOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

These values control how far and how long passenger/driver must separate before automatic offboarding.

### 24.8 Fare Configuration

```env
FARE_BASE_AMOUNT=17
FARE_BASE_DISTANCE_KM=4
FARE_ADDITIONAL_AMOUNT_PER_KM=2
```

These values support route fare calculations and fare snapshots.

### 24.9 Social/Firebase Configuration

```env
GOOGLE_CLIENT_IDS=
FACEBOOK_APP_TOKEN=
FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=
```

These are required only for the social/Firebase login paths that use them.

### 24.10 CORS And External Service Configuration

```env
CORS_ALLOWED_ORIGINS=
SMSAPIPH_API_KEY=
SMSAPIPH_BASE_URL=
TOMTOM_API_KEY=
GOOGLE_ROUTES_API_KEY=
```

These support:

- Allowed frontend origins.
- SMS API integration.
- Route/geocoding provider integrations where used.

`GOOGLE_ROUTES_API_KEY` is used only by the backend. In Google Cloud:

1. Select the intended Google Cloud project.
2. Attach a billing account.
3. Enable **Routes API**.
4. Create an API key.
5. Restrict the key to Routes API and, where practical, the backend's server/network environment.
6. Store it as the backend environment variable.

Do not select every Google Maps Platform API. ParaGO's current Google traffic route and ETA integration requires Routes API; unrelated APIs add unnecessary key exposure and quota surface.

### 24.11 Client Build-Time Configuration

The Flutter clients need a reachable API base URL.

Important client defines/configuration include:

- API base URL.
- Realtime enabled/disabled flag.
- Socket connection target derived from the API URL.

If the API URL is wrong:

- Login fails.
- Session restore fails.
- Route/trip data cannot load.
- Location automation cannot report.
- Realtime/polling cannot update.

If a newly added API such as `/announcements/admin` returns `404` from DigitalOcean while it exists locally, the deployed backend is older than the local source. Commit/push the backend changes and redeploy DigitalOcean before rebuilding clients around that endpoint.

### 24.12 Maps, Branding, And Release Artifacts

ParaGO keeps `flutter_map` for map rendering in admin, driver, and passenger clients. Google Routes API supplies route intelligence; it does not provide the map widget.

The Android apps use:

- App labels `SAKAY Driver` and `SAKAY Passenger`.
- SAKAY launcher icons.
- SAKAY centered native splash images.

Current release artifact names are:

```text
dist/sakay-driver.apk
dist/sakay-passenger.apk
```

These files are build artifacts, not live-updating packages. Rebuild and replace both APKs after mobile source changes before distributing them.

The checked-in native Android splash background is currently `#F8F4EA`. If the approved branding requires dark green, update both apps' `sakay_splash_background`, rebuild both release APKs, and visually verify the native startup frame before distribution.

## 25. Testing And Verification

### 25.1 Backend Test Suite

The backend test suite is documented in [TEST-SUITE-README.md](TEST-SUITE-README.md).

It validates business rules without needing to start the API server.

Current documented coverage includes:

- JWT and persistent session token behavior.
- Password hashing.
- Geolocation calculations.
- Input validation.
- Role authorization.
- Pickup request lifecycle.
- Boarding windows.
- Automatic onboard proximity timing.
- Automatic offboard separation timing.
- Hybrid terminal dispatch rules.
- Explicit route terminal settings.
- Terminal queue sorting and skipped-status handling.
- Stop alert cooldowns.
- Automatic reassignment pass-by checks.
- Destination approach checks.
- API response format.
- Trip state rules.
- Notification payload rules.
- Passenger traffic ETA destination validation, route sampling, passed-pickup rejection, and request cache keys.
- Announcement payload and timing status rules.
- Rate limit configuration.

The current backend command runs:

- 62 backend unit tests.
- 6 isolated announcement HTTP/database integration tests using in-memory MongoDB.

The announcement integration tests do not connect to or modify the configured development database.

### 25.2 One-Time Login Tests

Important tests include:

- Token generation.
- Token verification.
- Refresh token generation.
- Refresh token rotation state.

These verify that persistent login can work safely through refresh-token rotation.

### 25.3 Terminal Settings Tests

Terminal settings tests verify:

- Configured terminal resolution.
- Fallback terminal behavior.
- Disabled terminal behavior.
- Route terminal stop availability.

### 25.4 Terminal Queue Tests

Terminal queue tests verify:

- Queue sorting.
- Skipped status normalization.
- Skipped trips are treated differently from waiting/loading trips.

### 25.5 Automatic Onboarding Tests

Automatic onboarding tests verify:

- Near passenger before dwell time does not onboard yet.
- Near passenger after dwell time completes onboarding.
- Moving away resets proximity timing.

### 25.6 Automatic Offboarding Tests

Automatic offboarding tests verify:

- Separation before required checks/time does not complete ride yet.
- Repeated/sustained separation completes ride.
- Returning near the driver resets offboarding state.

### 25.7 Manual Real-Device Checklist

Use at least one passenger device and one driver device.

1. Log in once on each app.
2. Restart apps and confirm sessions restore.
3. Configure a route terminal in admin.
4. Start a driver trip in terminal queue mode.
5. Confirm the admin dashboard shows the terminal queue jeepney.
6. Reorder the queue and confirm order changes.
7. Skip a jeepney and confirm it stays visible.
8. Create a terminal passenger booking and confirm skipped jeepney is not selected.
9. Restore the jeepney and confirm it returns to active queue behavior.
10. Create a passenger request.
11. Driver acknowledges the request.
12. Keep passenger and driver close for more than 10 seconds.
13. Confirm automatic onboarding.
14. Confirm driver passenger count increases.
15. Move passenger and driver apart beyond separation distance.
16. Confirm automatic offboarding after repeated/sustained separation.
17. Confirm driver passenger count decreases.
18. Disable GPS or internet and confirm manual boarding/unload fallback remains usable.
19. Tap a visible jeep and confirm plate, seats, freshness, distance, and traffic ETA.
20. Confirm ETA uses the pickup pin before phone GPS.
21. Create a passenger support thread and exchange messages with admin.
22. Create a driver support thread and exchange messages with admin.
23. Disconnect realtime temporarily and confirm support refreshes through polling.
24. Restore network and confirm socket reconnection reconciles support and announcements.
25. Publish passenger-only, driver-only, and shared announcements.
26. Confirm audience isolation and severity styling.
27. Dismiss an announcement, edit it as admin, and confirm the new revision reappears.
28. Archive an active announcement and confirm cards disappear.
29. Disable the announcement endpoint temporarily and confirm core dashboards still load.
30. Test long support and announcement messages at desktop and narrow widths.

### 25.8 Announcement And Support Verification

Announcement verification includes:

- Authorization and audience isolation.
- Required critical and active-archive confirmation flags.
- Revision-specific dismissals and `409` stale-revision behavior.
- Pagination, filters, ordering, and maximum page size.
- Timestamp/range validation and immutable expired state.
- Concurrent scheduler reconciliation.

Support verification should include:

- Owner/admin authorization boundaries.
- Passenger and driver thread creation.
- Message, read, assignment, resolve, close, and reopen flows.
- Canonical `threadId` in realtime payloads.
- Reconnect reconciliation and 30-second polling.
- Long-message wrapping and narrow-screen behavior.
- Dashboard continuity when support endpoints fail.

### 25.9 Known Local Tooling Note

During the 2026-07-29 realtime/cache update:

- Backend unit and announcement integration tests passed.
- Targeted Dart analysis for changed passenger, driver, and admin files reported no issues.
- `git diff --check` passed.
- Focused Flutter widget-test commands could not acquire the Flutter SDK lock because other Flutter sessions were already running.
- Direct Dart commands completed analysis but the workspace sandbox prevented Dart from updating its global telemetry timestamp outside the repository.

Rerun focused Flutter widget tests after existing Flutter sessions release the SDK lock.

## 26. What Can Fail And What To Check

### 26.1 Login Fails

Check:

- API base URL.
- Backend is running.
- MongoDB is connected.
- User exists.
- Password is correct.
- User status is active.
- Role matches the app.
- JWT secrets are configured.

### 26.2 Session Restore Fails

Check:

- Tokens exist in local storage.
- Refresh token is not expired.
- Refresh token was not revoked by logout.
- JWT secrets did not change.
- Backend is reachable.
- User role still matches app.

### 26.3 Passenger Cannot Book

Check:

- Passenger has location permission.
- Selected route is active.
- Pickup is near route.
- Pickup is near passenger current location.
- Destination is valid and after pickup.
- Trip is active and accepting requests.
- Trip has capacity.
- Terminal route supports terminal booking if terminal mode is used.

### 26.4 Terminal Queue Not Visible

Check:

- Route terminal support is enabled.
- Trip is in terminal queue mode.
- Trip is active or scheduled as expected.
- Terminal queue status is not off queue unless expected.
- Admin dashboard loaded hybrid dispatch data.
- Admin session is valid.

### 26.5 Skipped Jeepney Still Receives Passengers

Check:

- Trip status is actually `skipped`.
- Dispatch board refreshed after skip.
- Passenger request is terminal type.
- Assignment logic is using terminal queue path.
- There is no stale client cache showing old assignment.

### 26.6 Automatic Onboarding Does Not Happen

Check:

- Pickup request is acknowledged.
- Trip is active.
- Passenger app is sending location.
- Driver app is sending location.
- Locations are recent.
- Passenger is within configured proximity.
- Passenger stayed close for more than configured dwell seconds.
- Manual boarding still works.

### 26.7 Automatic Offboarding Does Not Happen

Check:

- Ride is onboard.
- Passenger app is sending location.
- Driver app is sending location.
- Locations are recent.
- Distance exceeds configured offboarding distance.
- Outside checks or sustained time have completed.
- Passenger did not return near the jeepney.
- Manual unload still works.

### 26.8 Passenger Count Is Wrong

Check:

- Did boarding complete twice?
- Did ride completion fail?
- Is ride still onboard?
- Did GPS automation pause due to stale data?
- Did manual unload fail?
- Are driver/admin views showing stale cached data?
- Does backend trip occupancy match ride sessions?

### 26.9 Passenger ETA Is Unavailable

Check:

- `GOOGLE_ROUTES_API_KEY` exists in the deployed backend environment.
- Google Cloud billing is active.
- Routes API is enabled for that key.
- Trip and jeepney are active.
- Jeepney location is no older than 60 seconds.
- Destination coordinates are valid.
- Pickup/destination has not already been passed along the route snapshot.
- Google quota or API restrictions are not rejecting the server.

The passenger ETA intentionally returns unavailable instead of an average-speed fallback.

### 26.10 Support Chat Does Not Update

Check:

- `/support` routes are present in the deployed backend.
- User is the thread owner or an admin.
- Thread is not closed when sending a message.
- Socket is authenticated and joined to the correct user/role room.
- Support event contains `threadId`, `id`, or `_id`.
- The 30-second API refresh can reach the backend.
- A slower request is not being discarded correctly by a newer generation.

Support failure must not freeze maps, trips, bookings, or dashboard navigation.

### 26.11 Announcements Do Not Appear

Check:

- Announcement audience matches the current role.
- Status and current UTC time make it active.
- User has not dismissed the current revision.
- Announcement is not archived or expired.
- `/announcements/active` is deployed and reachable.
- Socket role room received the event or the next polling refresh completed.
- Critical confirmation was included when required.

Ordinary notification unread counts do not include announcements.

### 26.12 Admin Endpoint Returns 404

If the browser requests an endpoint that exists locally but production returns `404`, check:

- Latest backend changes were committed and pushed.
- DigitalOcean deployed the expected branch/commit.
- Build and start commands point to this repository's `src/server.js`.
- `/api/v1` prefix and compatibility route registration are active.
- The service was restarted after environment/configuration changes.

This is normally deployment version drift, not a Flutter rendering problem.

## 27. Related Documents

- [ONE_TIME_LOGIN.md](ONE_TIME_LOGIN.md)
- [TERMINAL_SETTINGS.md](TERMINAL_SETTINGS.md)
- [TERMINAL_QUEUE_MANAGEMENT.md](TERMINAL_QUEUE_MANAGEMENT.md)
- [AUTOMATIC_ONBOARDING.md](AUTOMATIC_ONBOARDING.md)
- [AUTOMATIC_OFFBOARDING.md](AUTOMATIC_OFFBOARDING.md)
- [AUTOMATIC_REASSIGNMENT.md](AUTOMATIC_REASSIGNMENT.md)
- [REALTIME_COMPLETE.md](REALTIME_COMPLETE.md)
- [REALTIME_GPS_IMPLEMENTATION.md](REALTIME_GPS_IMPLEMENTATION.md)
- [REALTIME_SUMMARY.md](REALTIME_SUMMARY.md)
- [TEST-SUITE-README.md](TEST-SUITE-README.md)
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)
- [PARAGO_System_Instruction_Manual.md](PARAGO_System_Instruction_Manual.md)
- [PARAGO_SYSTEM_NOTE.md](PARAGO_SYSTEM_NOTE.md)

## 28. Final Summary

ParaGO is a multi-app jeepney operations platform. Admins configure the system, publish announcements, answer support conversations, and monitor operations. Drivers operate trips and contact support. Passengers request and complete rides, inspect jeep plate/seat/location details, receive Google traffic-aware ETA, and contact support. The backend coordinates identity, route data, trip state, pickup requests, boarding, ride sessions, stop alerts, notifications, announcements, support threads, terminal queue behavior, passenger counts, routing intelligence, and reports.

The most important operational chain is:

1. Admin configures route, terminal, driver, and jeepney.
2. Driver starts a route or terminal queue trip.
3. Passenger creates a request.
4. Backend assigns the request.
5. Driver acknowledges it.
6. Passenger boards manually or automatically.
7. Passenger count increases.
8. Passenger rides and can send stop alert.
9. Passenger unloads manually or automatically.
10. Passenger count decreases.
11. Passenger and driver receive targeted service announcements.
12. Passenger or driver can open a support thread when assistance is needed.
13. Admin replies, resolves operational concerns, and monitors operations and reports.

Manual and polling fallbacks remain important throughout the system. Automatic features improve convenience and accuracy, but they intentionally pause when GPS, internet, provider availability, or state is not reliable enough to make a safe decision. Announcement or support failures are isolated from core trip, booking, map, and driver operations.
