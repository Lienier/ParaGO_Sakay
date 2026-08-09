# ParaGO! Admin Web App

This is the dedicated Flutter web client for ParaGO administrators.

It contains the admin console for:

- Driver and jeepney management
- Route building and route activation
- Landmark drop-off and fare management
- Operations dashboard and reports

## Folder

- `parago_admin_web/` is the standalone admin web app.
- Driver operations stay in `parago_mobile/`.

## Run setup

1. Go to `parago_admin_web`
2. `flutter pub get`
3. Configure API base URL at run time:

```bash
flutter run -d chrome --dart-define=PARAGO_API_BASE_URL=http://<your-backend-host>/api/v1
```

## Firebase setup

Firebase can still be configured for shared backend auth flows, while the admin
web app itself is intended for admin account sign-in only.

Configure Firebase for this app:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=sakayflutter-88a7b
```

Register the web app in your Google/Firebase project as needed for your setup.

- Generated files:
  - `lib/firebase_options.dart`

Run the app with the AWS backend URL:

```bash
flutter run -d chrome \
  --dart-define=PARAGO_API_BASE_URL=https://d2f5f4il9xhq8s.cloudfront.net/api/v1 \
  --dart-define=PARAGO_API_BASE_URLS=https://paragosakay-app-qulmw.ondigitalocean.app/api/v1 \
  --dart-define=PARAGO_ENABLE_REALTIME=false
```

The app no longer uses a bundled `.env`. Pass app config through `--dart-define`.

## Deploy on Vercel

This app now includes Vercel defaults in `vercel.json` and `vercel-build.sh`.

In Vercel, configure only these values:

1. Root Directory: `parago_admin_web`
2. Environment Variables:
  - `PARAGO_API_BASE_URL` = `https://d2f5f4il9xhq8s.cloudfront.net/api/v1`
  - `PARAGO_API_BASE_URLS` = `https://paragosakay-app-qulmw.ondigitalocean.app/api/v1`
  - `PARAGO_ENABLE_REALTIME` = `false`

Then deploy. Vercel will run `bash ./vercel-build.sh` and publish `build/web`.

Backend CORS reminder:

- Add your Vercel domain(s) to `CORS_ALLOWED_ORIGINS` on the backend service.

Backend note:

- Add Firebase Admin service-account values to the root `.env`.
- Add `TOMTOM_API_KEY` to the root `.env` for traffic-aware route previews.
- The backend verifies Firebase ID tokens, then creates or restores the MongoDB user.
- If Google sign-in fails on Android, add your Android SHA-1 in Firebase, enable
  Google in Firebase Authentication, then download a fresh
  `android/app/google-services.json`.

## Implemented route flows

- Auth
  - `POST /auth/register-email`
  - `POST /auth/login-email`
  - `POST /auth/social/{google|facebook}`
- Admin
  - `GET /admin/dashboard`
  - `GET /admin/recent-activity`
  - `GET /admin/drivers`
  - `PATCH /admin/drivers/{id}`
- Routes
  - `GET /routes`
  - `POST /routes`
  - `PUT /routes/{id}`

## Note

- This scaffold stores tokens in `SharedPreferences` via `TokenStorage`.
- Add secure storage plugin later if needed for stronger security hardening.
