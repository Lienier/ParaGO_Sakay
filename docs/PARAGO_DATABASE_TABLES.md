# ParaGO Database Tables

## Database Overview

| # | Collection | Main purpose | Key relationships |
|---:|---|---|---|
| 1 | `users` | Shared account and identity records | Parent of passengers, drivers, admins, notifications, tokens, logs, and reports |
| 2 | `passengers` | Passenger profile and emergency information | Belongs to `users`; used by pickup requests, rides, and stop alerts |
| 3 | `drivers` | Driver profile, verification, and assignments | Belongs to `users`; assigned to jeepneys and routes |
| 4 | `admins` | Administrator permissions and notes | Belongs to `users` |
| 5 | `jeepneys` | Jeepney/vehicle registry and live location | References the current driver; used by trips |
| 6 | `routes` | Route geometry, stops, navigation, and fare rules | Referenced by drivers, passengers, trips, pickup requests, and stop alerts |
| 7 | `tripsessions` | Scheduled and live trip operations | References a jeepney, driver, and route |
| 8 | `pickuprequests` | Passenger requests to be picked up | References a passenger, trip, route, and acknowledging driver |
| 9 | `ridesessions` | Passenger ride lifecycle after boarding | References a passenger, trip, and pickup request |
| 10 | `stopalerts` | Passenger request to get off at a stop | References a passenger, trip, ride, route, and acknowledging driver |
| 11 | `notifications` | In-app user notifications | Belongs to a user |
| 12 | `activitylogs` | Audit trail of system and admin actions | References the acting user |
| 13 | `refreshtokens` | Long-lived authentication sessions | Belongs to a user |
| 14 | `passwordresettokens` | Password recovery tokens | Belongs to a user |
| 15 | `adminloginchallenges` | One-time admin login verification challenges | Belongs to a user |
| 16 | `reportmetadata` | Generated report information and summaries | References the user who generated the report |

> **Database technology:** MongoDB (document database) with Mongoose. Each collection uses `_id` as its primary identifier. Fields marked `FK` are MongoDB `ObjectId` references; embedded objects are stored inside their parent document.

## Detailed Table Definitions

### 1. `users`

Shared identity record for passengers, drivers, and administrators.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `email` | String | Required, unique |
| `passwordHash` | String | Optional, hidden by default |
| `fullName` | String | Required |
| `phone` | String | Optional |
| `role` | String | Required: `PASSENGER`, `DRIVER`, `ADMIN` |
| `authProvider` | String | Required: `local`, `google`, `facebook` |
| `providerId` | String | Optional; unique with auth provider when present |
| `status` | String | Required: `active`, `suspended`, `deactivated` |
| `isVerified` | Boolean | Default: `false` |
| `lastLoginAt` | Date | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 2. `passengers`

Passenger profile extension linked one-to-one with a user account.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required, unique |
| `phone` | String | Optional |
| `photoUrl` | String | Optional |
| `emergencyContact` | Embedded | Name and phone |
| `defaultRouteId` | ObjectId | FK → `routes`, optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 3. `drivers`

Driver operational profile and vehicle/route assignments.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required, unique |
| `licenseNumber` | String | Optional |
| `employeeNumber` | String | Optional |
| `phone` | String | Optional |
| `assignedJeepneyId` | ObjectId | FK → `jeepneys`, optional |
| `assignedRouteId` | ObjectId | FK → `routes`, optional |
| `isVerified` | Boolean | Default: `false` |
| `status` | String | `active` or `inactive` |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 4. `admins`

Administrator profile and access permissions.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required, unique |
| `permissions` | Array of String | Optional |
| `notes` | String | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 5. `jeepneys`

Vehicle registry, capacity, assignment, and most recent location.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `plateNumber` | String | Required, unique |
| `capacity` | Number | Minimum: 1 |
| `vehicleTag`, `jeepneyName`, `manufacturer` | String | Optional |
| `capacityBand` | String | Default: `normal` |
| `status` | String | `active`, `inactive`, `maintenance` |
| `currentDriverId` | ObjectId | FK → `drivers`, optional |
| `lastKnownLocation` | GeoPoint | Optional, 2dsphere indexed |
| `lastSeenAt` | Date | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 6. `routes`

Transport route definition with geometry, stops, navigation metadata, and fare configuration.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `name` | String | Required |
| `code` | String | Required, unique |
| `direction` | String | `up`, `down`, `circular` |
| `status` | String | `active` or `inactive` |
| `description` | String | Optional |
| `path` | GeoJSON LineString | Optional, 2dsphere indexed |
| `waypoints` | Array of Waypoint | Embedded |
| `stops` | Array of RouteStop | Embedded |
| `navigation` | RouteNavigation | Embedded, optional |
| `fareConfig` | FareConfig | Embedded, required |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 7. `tripsessions`

Scheduled or live jeepney trip tied to a route.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `jeepneyId` | ObjectId | FK → `jeepneys`, required |
| `driverId` | ObjectId | FK → `drivers`, optional |
| `routeId` | ObjectId | FK → `routes`, required |
| `routePathSnapshot` | GeoJSON LineString | Optional |
| `status` | String | `scheduled`, `active`, `completed`, `cancelled` |
| `startedAt`, `endedAt` | Date | Optional |
| `acceptRequests` | Boolean | Default: `true` |
| `occupancyCount` | Number | Default: `0`, minimum: 0 |
| `active` | Boolean | Default: `false` |
| `notes` | String | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 8. `pickuprequests`

Passenger pickup request for a particular trip and route.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `passengerId` | ObjectId | FK → `passengers`, required |
| `tripSessionId` | ObjectId | FK → `tripsessions`, required |
| `routeId` | ObjectId | FK → `routes`, required |
| `stopRef`, `destinationStopRef` | String | Optional stop identifiers |
| `pickupLocation`, `destinationLocation` | GeoPoint | Optional |
| `fareSnapshot` | FareSnapshot | Embedded, optional |
| `status` | String | `pending`, `acknowledged`, `completed`, `expired`, `cancelled` |
| `acknowledgedBy` | ObjectId | FK → `drivers`, optional |
| `acknowledgedAt` | Date | Optional |
| `sourceNote` | String | Optional |
| `expiresAt` | Date | Required; TTL expiration |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 9. `ridesessions`

Ride record created after boarding validation.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `passengerId` | ObjectId | FK → `passengers`, required |
| `tripSessionId` | ObjectId | FK → `tripsessions`, required |
| `pickupRequestId` | ObjectId | FK → `pickuprequests`, required |
| `destinationStopRef` | String | Optional |
| `destinationLocation` | GeoPoint | Optional, 2dsphere indexed |
| `fareSnapshot` | FareSnapshot | Embedded, optional |
| `status` | String | `waiting`, `onboard`, `completed` |
| `boardedAt`, `endedAt` | Date | Optional |
| `canSendStopAlert` | Boolean | Default: `false` |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 10. `stopalerts`

Digital para or unload request associated with an active ride.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `passengerId` | ObjectId | FK → `passengers`, required |
| `tripSessionId` | ObjectId | FK → `tripsessions`, required |
| `rideSessionId` | ObjectId | FK → `ridesessions`, required |
| `routeId` | ObjectId | FK → `routes`, required |
| `stopRef` | String | Optional |
| `note` | String | Optional |
| `status` | String | `sent`, `seen`, `acknowledged`, `dismissed` |
| `acknowledgedBy` | ObjectId | FK → `drivers`, optional |
| `acknowledgedAt` | Date | Optional |
| `location` | GeoPoint | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 11. `notifications`

In-app notifications delivered to users.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required |
| `type`, `title`, `body`, `category` | String | Notification information |
| `payload` | Mixed | Optional additional data |
| `readAt` | Date | Optional |
| `isRead` | Boolean | Read status |
| `expiresAt` | Date | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 12. `activitylogs`

Audit records of user and administrator actions.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `actorId` | ObjectId | FK → `users`, optional |
| `actorRole` | String | Role at time of action |
| `action`, `entity`, `entityId` | String | Action and affected record |
| `details` | Mixed | Optional event details |
| `ip`, `client` | String | Request source information |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 13. `refreshtokens`

Refresh-token records for persistent authentication sessions.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required |
| `tokenHash` | String | Required, unique |
| `expiresAt` | Date | Required |
| `revokedAt` | Date | Optional |
| `replacedByHash` | String | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 14. `passwordresettokens`

Short-lived password recovery records.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required |
| `tokenHash` | String | Required, unique |
| `expiresAt` | Date | Required, TTL expiration |
| `usedAt` | Date | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 15. `adminloginchallenges`

One-time verification challenges for administrator login.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `userId` | ObjectId | FK → `users`, required |
| `phone` | String | Required |
| `codeHash` | String | Required |
| `expiresAt` | Date | Required, TTL expiration |
| `attempts` | Number | Default: `0` |
| `maxAttempts` | Number | Default: `5` |
| `usedAt` | Date | Optional |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

### 16. `reportmetadata`

Metadata and summary information for generated administrator reports.

| Field | Type | Key / rule |
|---|---|---|
| `_id` | ObjectId | PK |
| `reportType` | String | Required |
| `periodStart`, `periodEnd` | Date | Required reporting period |
| `generatedBy` | ObjectId | FK → `users`, required |
| `params` | Mixed | Report parameters; default `{}` |
| `resultSummary` | Mixed | Report summary; default `{}` |
| `fileUrl` | String | Optional generated-file location |
| `createdAt`, `updatedAt` | Date | Automatic timestamps |

## Embedded Documents

These are not separate collections. They are stored inside their parent documents.

| Embedded document | Stored in | Main fields |
|---|---|---|
| `EmergencyContact` | `passengers.emergencyContact` | `name`, `phone` |
| `GeoPoint` | Vehicles, routes, pickup requests, rides, stop alerts | `type`, `coordinates` |
| `Waypoint` | `routes.waypoints[]` | `name`, `location` |
| `RouteStop` | `routes.stops[]` | `name`, `code`, `order`, `fare`, `location` |
| `RouteBounds` | `routes.navigation.bounds` | `north`, `south`, `east`, `west` |
| `FareConfig` | `routes.fareConfig` | `baseAmount`, `baseDistanceKm`, `additionalAmountPerKm` |
| `RouteNavigation` | `routes.navigation` | Source, traffic, origin/destination, distance, duration |
| `FareSnapshot` | Pickup and ride sessions | Boarding fare, destination fare, total amount |

## Primary Relationships

| Parent collection | Child collection | Reference field | Cardinality |
|---|---|---|---|
| `users` | `passengers` | `passengers.userId` | One-to-zero/one |
| `users` | `drivers` | `drivers.userId` | One-to-zero/one |
| `users` | `admins` | `admins.userId` | One-to-zero/one |
| `jeepneys` | `tripsessions` | `tripsessions.jeepneyId` | One-to-many |
| `drivers` | `tripsessions` | `tripsessions.driverId` | One-to-many |
| `routes` | `tripsessions` | `tripsessions.routeId` | One-to-many |
| `passengers` | `pickuprequests` | `pickuprequests.passengerId` | One-to-many |
| `tripsessions` | `pickuprequests` | `pickuprequests.tripSessionId` | One-to-many |
| `passengers` | `ridesessions` | `ridesessions.passengerId` | One-to-many |
| `pickuprequests` | `ridesessions` | `ridesessions.pickupRequestId` | One-to-many |
| `ridesessions` | `stopalerts` | `stopalerts.rideSessionId` | One-to-many |
| `users` | `notifications` | `notifications.userId` | One-to-many |
| `users` | `activitylogs` | `activitylogs.actorId` | One-to-many |
| `users` | `refreshtokens` | `refreshtokens.userId` | One-to-many |
| `users` | `passwordresettokens` | `passwordresettokens.userId` | One-to-many |
| `users` | `adminloginchallenges` | `adminloginchallenges.userId` | One-to-many |
| `users` | `reportmetadata` | `reportmetadata.generatedBy` | One-to-many |

## Presentation Notes

- **PK:** Primary key generated by MongoDB as an `ObjectId`.
- **FK:** Application-level reference to another collection using `ObjectId`.
- **Embedded:** Nested document stored inside the parent collection; it does not have its own collection.
- **TTL:** MongoDB automatically removes the document after the expiration date.
- Timestamps `createdAt` and `updatedAt` are automatically maintained by Mongoose.
