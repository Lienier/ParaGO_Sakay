# ParaGO! Flutter Client Scaffold

This is the practical thesis-focused mobile client scaffold for:

- Passenger onboarding + pickup request
- Boarding verification flow
- Digital stop alerts
- Driver trip controls and request monitoring
- Admin dashboard summary
- Google/Facebook/email authentication entry points

## Folder

- `parago_mobile/` is a standalone Flutter app.

## Run setup

1. Go to `parago_mobile`
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
flutterfire configure --project=parago-ba422
```

Register this Android app in your Google/Firebase project:

- Package name: `com.example.parago_mobile`
- Debug SHA-1: `56:E2:09:88:11:D7:AA:A7:9C:CA:6B:3E:4F:61:02:97:3D:31:61:EB`
- Generated files:
  - `lib/firebase_options.dart`
  - `android/app/google-services.json`

Run the app with the backend URL:

```bash
flutter run -d <device> --dart-define=PARAGO_API_BASE_URL=http://<your-backend-host>/api/v1
```

Backend note:

- Add Firebase Admin service-account values to the root `.env`.
- The backend verifies Firebase ID tokens, then creates or restores the MongoDB user.

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
