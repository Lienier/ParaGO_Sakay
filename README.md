# ParaGO! Backend Scaffold

This scaffold is built for a thesis-oriented transportation support system using:

- Node.js + Express
- MongoDB Atlas (Mongoose)
- JWT authentication
- Heroku-ready server entrypoint

It implements a modular backend for passenger/driver/admin roles with:

- Authentication (email login + social login endpoints)
- Authentication (email login + Firebase-backed Google login)
- Trip session management
- Pickup requests
- Boarding validation
- Ride sessions
- Stop alerts (digital “para”)
- Notifications
- Admin dashboard and reporting endpoints

## Project structure

- `src/app.js` – Express app with route registration and middleware
- `src/server.js` – Application entrypoint for startup
- `src/config` – env + database connection helpers
- `src/models` – Mongoose schemas for all core collections
- `src/services` – domain services (auth, boarding, stop alert)
- `src/middlewares` – auth/role/error helpers
- `src/utils` – shared helpers (JWT, API response shape, async wrapper)
- `src/routes` – REST route modules

## Setup

1. Install dependencies:
   `npm install`
2. Fill in `.env` with the required values:
   - `MONGO_URI`
   - `JWT_SECRET`
   - `JWT_REFRESH_SECRET`
   - social login keys if used
   - Firebase Admin service-account values for Google login
3. Start dev server:
   `npm run dev`
4. Start production server:
   `npm start`

## Environment variables

- `NODE_ENV`
- `PORT`
- `MONGO_URI`
- `JWT_SECRET`
- `JWT_EXPIRES_IN`
- `JWT_REFRESH_SECRET`
- `JWT_REFRESH_EXPIRES_IN`
- `BOARDING_WINDOW_MINUTES`
- `STOP_ALERT_COOLDOWN_MINUTES`
- `PICKUP_REQUEST_TTL_MINUTES`
- `MAX_REQUESTS_PER_PASSENGER_PER_TRIP`
- `GOOGLE_CLIENT_IDS`
- `FACEBOOK_APP_TOKEN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

## API groups (v1)

- `/api/v1/auth`
- `/api/v1/users`
- `/api/v1/passengers`
- `/api/v1/drivers`
- `/api/v1/admin`
- `/api/v1/jeepneys`
- `/api/v1/routes`
- `/api/v1/trips`
- `/api/v1/pickup-requests`
- `/api/v1/boarding`
- `/api/v1/ride-sessions`
- `/api/v1/stop-alerts`
- `/api/v1/notifications`
- `/api/v1/reports`

## Auth endpoints (implemented)

- `POST /api/v1/auth/register-email`
- `POST /api/v1/auth/login-email`
- `POST /api/v1/auth/firebase/google`
- `POST /api/v1/auth/social/google`
- `POST /api/v1/auth/social/facebook` (disabled when `FACEBOOK_APP_TOKEN` is empty)
- `POST /api/v1/auth/refresh` (refresh-token rotation)
- `POST /api/v1/auth/logout` (refresh-token revocation)
- `POST /api/v1/auth/change-password`
- `POST /api/v1/auth/forgot-password`
- `POST /api/v1/auth/reset-password`
- `GET /api/v1/auth/me`

## Notes

- No QR code flow is implemented.
- Google login can be handled through Firebase Authentication while MongoDB remains the
  main application database and session source of truth.
- Boarding and stop alert use contextual checks:
  - valid active trip
  - pending/acknowledged request state
  - pickup request expiry
  - optional proximity check when coordinates are provided
- This scaffold is intentionally kept minimal to support iterative thesis development.
- In development mode, `forgot-password` returns a temporary reset token in response so thesis testing can proceed without SMTP setup.
