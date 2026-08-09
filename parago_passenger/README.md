# ParaGO Passenger App

This is the dedicated passenger mobile app for ParaGO. It shares the same backend
and database as the driver/admin systems, but the UI and navigation are trimmed
to passenger flows only.

- Passenger onboarding + pickup request
- Boarding verification flow
- Digital stop alerts
- Passenger-focused authentication entry points

## Folder

- `parago_passenger/` is a standalone Flutter app.

## Run setup

1. Go to `parago_passenger`
2. `flutter pub get`
3. Configure API base URL at run time:

```bash
flutter run -d <device> --dart-define=PARAGO_API_BASE_URL=http://<your-backend-host>/api/v1
```

If running on emulator with backend on local machine:

- Android emulator: `http://10.0.2.2:5000/api/v1`
- iOS simulator: `http://127.0.0.1:5000/api/v1`

## Firebase Google login setup

Google sign-in now uses Firebase Authentication on the Flutter side, while the
ParaGO backend still issues the real app session and stores users in MongoDB.

Configure Firebase for this app:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=sakayflutter-88a7b
```

Register this Android app in your Google/Firebase project:

- Package name: `com.parago.passenger`
- Debug SHA-1: `56:E2:09:88:11:D7:AA:A7:9C:CA:6B:3E:4F:61:02:97:3D:31:61:EB`
- Generated files:
  - `lib/firebase_options.dart`
  - `android/app/google-services.json`

Run the app with the AWS backend URL:

```bash
flutter run -d <device> \
  --dart-define=PARAGO_API_BASE_URL=https://d1d7vl5uwus519.cloudfront.net/api/v1 \
  --dart-define=PARAGO_API_BASE_URLS=https://paragosakay-app-qulmw.ondigitalocean.app/api/v1 \
  --dart-define=ORS_API_KEY=<your-openrouteservice-key> \
  --dart-define=PARAGO_ENABLE_REALTIME=true
```

The app no longer uses a bundled `.env`. Pass app config through `--dart-define`.
DigitalOcean remains available as a fallback URL; set `PARAGO_API_BASE_URL`
back to the DigitalOcean URL when you need to temporarily restore it.

The batched route-location protocol is staged but disabled by default. Enable
it only against a compatible backend build:

```powershell
flutter run -d <device> `
  --dart-define=PARAGO_ENABLE_ROUTE_LOCATION_BATCHES=true
```

Until the coordinated protocol cutover, the backend continues emitting the
authorized legacy location event alongside route batches.

Backend note:

- Add Firebase Admin service-account values to the root `.env`.
- The backend verifies Firebase ID tokens, then creates or restores the MongoDB user.
- If Google sign-in fails on Android, add your Android SHA-1 in Firebase, enable
  Google in Firebase Authentication, then download a fresh
  `android/app/google-services.json`.

## Implemented route flows

- Auth
  - `POST /auth/register-email`
  - `POST /auth/login-email`
  - `POST /auth/social/{google|facebook}`
- Trips
  - `GET /trips/active`
  - `GET /trips/mine`
  - `PATCH /trips/{id}/start`
  - `PATCH /trips/{id}/end`
  - `PATCH /trips/{id}/availability`
- Pickup requests
  - `GET /pickup-requests/mine`
  - `POST /pickup-requests`
  - `PATCH /pickup-requests/{id}/cancel`
  - `PATCH /pickup-requests/{id}/acknowledge`
- Boarding
  - `POST /boarding/validate`
- Ride sessions
  - `GET /ride-sessions/mine`
- Stop alerts
  - `POST /stop-alerts`
- Notifications
  - `GET /notifications/mine`
  - `PATCH /notifications/{id}/read`
- Admin
  - `GET /admin/dashboard`
  - `GET /admin/recent-activity`

## Note

- This scaffold stores tokens in `SharedPreferences` via `TokenStorage`.
- Add secure storage plugin later if needed for stronger security hardening.
