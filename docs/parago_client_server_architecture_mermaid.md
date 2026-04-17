# ParaGO Client-Server Architecture Mermaid Code

## Figure. ParaGO Client-Server Architecture

```mermaid
flowchart LR
    subgraph C[Client Side]
        C1[Passenger Mobile App\nFlutter]
        C2[Driver Mobile App\nFlutter]
        C3[Admin Web App\nFlutter Web]
        C4[Users\nPassengers, Drivers, Admins]
    end

    I((Internet))

    subgraph S[Server Side]
        S1[ParaGO Backend API\nNode.js and Express]
        S2[Authentication and Session Handling\nJWT and Refresh Tokens]
        S3[Realtime Communication\nSocket.IO]
        S4[Database\nMongoDB Atlas]
        S5[External Auth Support\nFirebase Authentication]
    end

    C1 --> I
    C2 --> I
    C3 --> I
    C4 --> C1
    C4 --> C2
    C4 --> C3

    I -->|HTTP Request| S1
    S1 -->|HTTP Response| I
    S1 --> S2
    S1 --> S3
    S1 --> S4
    S1 --> S5
```

## Alternative Thesis-Friendly Version

```mermaid
flowchart LR
    subgraph CLIENT[Client Side]
        A1[Passenger App]
        A2[Driver App]
        A3[Admin Web App]
    end

    NET((Internet))

    subgraph SERVER[Server Side]
        B1[Application Server\nExpress Backend]
        B2[Authentication Module]
        B3[Realtime Module]
        B4[MongoDB Database]
    end

    A1 -->|Request| NET
    A2 -->|Request| NET
    A3 -->|Request| NET

    NET -->|Request| B1
    B1 -->|Response| NET

    B1 --> B2
    B1 --> B3
    B1 --> B4
```

## Thesis Description

The ParaGO system follows a client-server architecture. On the client side, the system provides three user-facing applications: the passenger mobile application, the driver mobile application, and the admin web application. These clients communicate over the internet with the ParaGO backend server developed using Node.js and Express. The server is responsible for processing requests, managing authentication and sessions, handling realtime communication, and storing operational data in MongoDB. Firebase Authentication is also integrated to support selected authentication flows. This architecture enables centralized business logic, shared data access, and coordinated transport operations across all user roles.

## Notes

- Use the first figure if you want to explicitly show the actual technologies.
- Use the second figure if your adviser prefers a cleaner and more traditional thesis diagram.
- This is a client-server architecture figure, not a layered client architecture figure.
