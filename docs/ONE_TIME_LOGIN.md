# One-Time Login

## Meaning

In ParaGO, one-time login means users should not need to sign in every time they open the passenger, driver, or admin app. A user signs in once, the app saves the issued tokens, and the session is restored on the next launch unless the user logs out or the refresh token becomes invalid.

## Current Implementation

The backend issues two tokens after successful login:

- access token: used for authenticated API calls
- refresh token: used to get a new access token when the old one expires

Refresh tokens are stored in MongoDB as hashes, not raw token strings. When a refresh token is used, the backend rotates it by issuing a new refresh token and revoking the old one.

The three Flutter apps use the same restore pattern:

- `TokenStorage` saves `accessToken` and `refreshToken` in shared preferences.
- `SessionController.restore()` loads the saved tokens on startup.
- If the saved access token is valid, the app calls `/auth/me` and continues.
- If the access token fails but a refresh token exists, the app calls `/auth/refresh`, saves the new tokens, and continues.
- Logout revokes the refresh token server-side and clears local storage.

## Role Guarding

Each app only accepts the role it is built for:

- passenger app accepts passenger sessions
- driver app accepts driver sessions
- admin web accepts admin sessions

If a saved token belongs to the wrong role, the app clears the local session and returns to login.

## Expected User Flow

1. User logs in successfully.
2. App stores the access and refresh tokens.
3. User closes the app.
4. User opens the app again.
5. App restores the session automatically.
6. User is sent directly to the correct home screen.

The user should only need to log in again when:

- they manually log out
- their account is deactivated or suspended
- the refresh token expires
- the saved token is invalid or belongs to the wrong app role

## Verification

Run:

```bash
npm test
```

The backend suite includes `JWT - Refresh Token Rotation State`, which verifies the refresh-token replacement rule used by persistent login.

Manual app verification:

1. Log in to passenger, driver, or admin.
2. Close the app/browser tab.
3. Reopen it.
4. Confirm it opens the home screen without asking for login.
5. Log out.
6. Reopen it and confirm it asks for login.
