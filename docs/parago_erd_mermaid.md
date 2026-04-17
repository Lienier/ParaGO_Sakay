# ParaGO ERD Mermaid Code

## Figure 1. User and Access Management ERD

```mermaid
erDiagram
    USER {
        ObjectId _id PK
        string email UK
        string passwordHash
        string fullName
        string phone
        string role
        string authProvider
        string providerId
        string status
        boolean isVerified
        date lastLoginAt
    }

    PASSENGER {
        ObjectId _id PK
        ObjectId userId FK
        string phone
        string photoUrl
        string emergencyContactName
        string emergencyContactPhone
        ObjectId defaultRouteId FK
    }

    DRIVER {
        ObjectId _id PK
        ObjectId userId FK
        string licenseNumber
        string employeeNumber
        string phone
        ObjectId assignedJeepneyId FK
        ObjectId assignedRouteId FK
        boolean isVerified
        string status
    }

    ADMIN {
        ObjectId _id PK
        ObjectId userId FK
        string permissions
        string notes
    }

    NOTIFICATION {
        ObjectId _id PK
        ObjectId userId FK
        string type
        string title
        string body
        boolean isRead
        string category
        date readAt
        date expiresAt
    }

    REFRESH_TOKEN {
        ObjectId _id PK
        ObjectId userId FK
        string tokenHash UK
        date expiresAt
        date revokedAt
        string replacedByHash
    }

    PASSWORD_RESET_TOKEN {
        ObjectId _id PK
        ObjectId userId FK
        string tokenHash UK
        date expiresAt
        date usedAt
    }

    ADMIN_LOGIN_CHALLENGE {
        ObjectId _id PK
        ObjectId userId FK
        string phone
        string codeHash
        date expiresAt
        int attempts
        int maxAttempts
        date usedAt
    }

    ACTIVITY_LOG {
        ObjectId _id PK
        ObjectId actorId FK
        string actorRole
        string action
        string entity
        string entityId
        string ip
        string client
    }

    REPORT_METADATA {
        ObjectId _id PK
        string reportType
        date periodStart
        date periodEnd
        ObjectId generatedBy FK
        string fileUrl
    }

    USER ||--o| PASSENGER : has
    USER ||--o| DRIVER : has
    USER ||--o| ADMIN : has
    USER ||--o{ NOTIFICATION : receives
    USER ||--o{ REFRESH_TOKEN : owns
    USER ||--o{ PASSWORD_RESET_TOKEN : resets
    USER ||--o{ ADMIN_LOGIN_CHALLENGE : verifies
    USER ||--o{ ACTIVITY_LOG : performs
    USER ||--o{ REPORT_METADATA : generates
```

## Figure 2. Transport Operations ERD

```mermaid
erDiagram
    DRIVER {
        ObjectId _id PK
        ObjectId userId FK
        string licenseNumber
        string employeeNumber
        ObjectId assignedJeepneyId FK
        ObjectId assignedRouteId FK
        boolean isVerified
        string status
    }

    JEEPNEY {
        ObjectId _id PK
        string plateNumber UK
        int capacity
        string vehicleTag
        string jeepneyName
        string manufacturer
        string capacityBand
        string status
        ObjectId currentDriverId FK
        string lastKnownLocation
        date lastSeenAt
    }

    ROUTE {
        ObjectId _id PK
        string name
        string code UK
        string direction
        string status
        string description
        string path
        string fareConfig
        string navigation
    }

    ROUTE_STOP {
        string name
        string code
        int order
        float fare
        string location
    }

    WAYPOINT {
        string name
        string location
    }

    ROUTE_NAVIGATION {
        string source
        string trafficProfile
        string origin
        string destination
        float distanceMeters
        float durationSeconds
    }

    FARE_CONFIG {
        float baseAmount
        float baseDistanceKm
        float additionalAmountPerKm
    }

    TRIP_SESSION {
        ObjectId _id PK
        ObjectId jeepneyId FK
        ObjectId driverId FK
        ObjectId routeId FK
        string routePathSnapshot
        string status
        date startedAt
        date endedAt
        boolean acceptRequests
        int occupancyCount
        boolean active
    }

    JEEPNEY ||--o{ DRIVER : assigned_to
    ROUTE ||--o{ DRIVER : assigned_to
    DRIVER ||--o{ JEEPNEY : currently_drives
    JEEPNEY ||--o{ TRIP_SESSION : used_in
    DRIVER ||--o{ TRIP_SESSION : operates
    ROUTE ||--o{ TRIP_SESSION : defines
    ROUTE ||--o{ ROUTE_STOP : contains
    ROUTE ||--o{ WAYPOINT : includes
    ROUTE ||--|| ROUTE_NAVIGATION : has
    ROUTE ||--|| FARE_CONFIG : uses
```

## Figure 3. Passenger Ride Workflow ERD

```mermaid
erDiagram
    PASSENGER {
        ObjectId _id PK
        ObjectId userId FK
        string phone
        string photoUrl
        ObjectId defaultRouteId FK
    }

    DRIVER {
        ObjectId _id PK
        ObjectId userId FK
        ObjectId assignedJeepneyId FK
        ObjectId assignedRouteId FK
        string status
    }

    ROUTE {
        ObjectId _id PK
        string name
        string code UK
        string direction
        string status
    }

    TRIP_SESSION {
        ObjectId _id PK
        ObjectId jeepneyId FK
        ObjectId driverId FK
        ObjectId routeId FK
        string status
        boolean acceptRequests
        int occupancyCount
        boolean active
    }

    FARE_SNAPSHOT {
        string boardingStopRef
        int boardingStopOrder
        float boardingFare
        string destinationStopRef
        int destinationStopOrder
        float destinationFare
        float amount
    }

    PICKUP_REQUEST {
        ObjectId _id PK
        ObjectId passengerId FK
        ObjectId tripSessionId FK
        ObjectId routeId FK
        string stopRef
        string pickupLocation
        string destinationStopRef
        string destinationLocation
        string status
        ObjectId acknowledgedBy FK
        date acknowledgedAt
        date expiresAt
    }

    RIDE_SESSION {
        ObjectId _id PK
        ObjectId passengerId FK
        ObjectId tripSessionId FK
        ObjectId pickupRequestId FK
        string destinationStopRef
        string destinationLocation
        string status
        date boardedAt
        date endedAt
        boolean canSendStopAlert
    }

    STOP_ALERT {
        ObjectId _id PK
        ObjectId passengerId FK
        ObjectId tripSessionId FK
        ObjectId rideSessionId FK
        ObjectId routeId FK
        string stopRef
        string note
        string status
        ObjectId acknowledgedBy FK
        date acknowledgedAt
        string location
    }

    PASSENGER ||--o{ PICKUP_REQUEST : creates
    TRIP_SESSION ||--o{ PICKUP_REQUEST : receives
    ROUTE ||--o{ PICKUP_REQUEST : follows
    DRIVER ||--o{ PICKUP_REQUEST : acknowledges
    PASSENGER ||--o{ RIDE_SESSION : boards
    TRIP_SESSION ||--o{ RIDE_SESSION : contains
    PICKUP_REQUEST ||--o{ RIDE_SESSION : becomes
    PASSENGER ||--o{ STOP_ALERT : sends
    TRIP_SESSION ||--o{ STOP_ALERT : occurs_on
    RIDE_SESSION ||--o{ STOP_ALERT : triggers
    ROUTE ||--o{ STOP_ALERT : references
    DRIVER ||--o{ STOP_ALERT : acknowledges
    PICKUP_REQUEST ||--|| FARE_SNAPSHOT : has
    RIDE_SESSION ||--|| FARE_SNAPSHOT : has
```

## Notes

- `PK` means primary key.
- `FK` means foreign key style reference in MongoDB/Mongoose.
- `UK` means unique key.
- Embedded MongoDB objects were modeled as separate ERD items only where helpful for thesis readability.
