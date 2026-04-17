# ParaGO Client Layered Architecture Mermaid Code

## Figure. ParaGO Client Layered Architecture

```mermaid
flowchart TD
    A[Presentation Layer\nScreens, Widgets, Theme]
    B[State Management Layer\nSessionController, Provider]
    C[Service Layer\nAuthService, TripService, RouteService,\nNotificationService, StopAlertService]
    D[Data and Model Layer\nAuth Models, Trip Models, Route Models,\nPickup Request, Ride Session, Notification Models]
    E[Infrastructure Layer\nApiClient, TokenStorage, AppConfig,\nFirebaseAuthService, RealtimeSocketService]
    F[External Services\nREST API Backend, Firebase, Socket.IO]

    A --> B
    B --> C
    C --> D
    C --> E
    E --> F
```

## Alternative Version With Concrete Project Mapping

```mermaid
flowchart TD
    subgraph L1[Presentation Layer]
        P1[main.dart]
        P2[screens/auth_screen.dart]
        P3[screens/passenger or driver or admin home screens]
        P4[widgets and theme]
    end

    subgraph L2[Application and State Layer]
        A1[services/session_controller.dart]
        A2[Provider ChangeNotifier]
    end

    subgraph L3[Service Layer]
        S1[services/auth_service.dart]
        S2[services/trip_service.dart]
        S3[services/route_service.dart]
        S4[services/notification_service.dart]
        S5[services/stop_alert_service.dart]
        S6[services/passenger_service or driver_service or admin_service]
    end

    subgraph L4[Model Layer]
        M1[models/auth]
        M2[models/trip]
        M3[models/transport]
        M4[models/operations]
        M5[models/user_role.dart]
    end

    subgraph L5[Infrastructure Layer]
        I1[core/network/api_client.dart]
        I2[core/storage/token_storage.dart]
        I3[core/config/app_config.dart]
        I4[services/firebase_auth_service.dart]
        I5[services/realtime_socket_service.dart]
    end

    subgraph L6[External Systems]
        X1[ParaGO Backend API]
        X2[Firebase Authentication]
        X3[Realtime Socket Server]
    end

    P1 --> A1
    P2 --> A1
    P3 --> A1
    P4 --> P3
    A1 --> A2
    A1 --> S1
    A1 --> I2
    S1 --> M1
    S2 --> M2
    S3 --> M3
    S4 --> M4
    S5 --> M4
    S6 --> M2
    S6 --> M3
    S1 --> I1
    S2 --> I1
    S3 --> I1
    S4 --> I1
    S5 --> I1
    S6 --> I1
    A1 --> I1
    I1 --> X1
    I4 --> X2
    I5 --> X3
```

## Thesis Description

The ParaGO client applications use a layered architecture. The presentation layer contains the Flutter screens, widgets, and theme files responsible for the user interface. The state management layer is centered on `SessionController` with `Provider`, which manages authentication state, session restoration, and UI updates. The service layer contains application-specific services such as authentication, trip, route, notification, and stop alert services. These services use the data and model layer, which defines the client-side models for authentication, transport, trip, and operational records. Beneath them is the infrastructure layer, which handles API communication, token persistence, runtime configuration, Firebase integration, and realtime socket connectivity. This layered structure is shared across the passenger, driver, and admin clients, promoting separation of concerns, maintainability, and reuse.

## Notes

- This diagram represents the shared client architecture of `parago_passenger`, `parago_mobile`, and `parago_admin_web`.
- `SessionController` acts as the main application/state coordination layer in all three clients.
- `ApiClient` is the primary gateway to the backend API.
- `TokenStorage`, Firebase, and realtime services belong to the infrastructure layer rather than the UI layer.
