# Security repair release procedure

This change deliberately rejects legacy tokens. It is not deployed merely by editing these files. Real email sending, DNS changes, infrastructure applies and the database cutover are release actions.

## Prerequisites

- Use the project's supported Node 22 runtime and a MongoDB replica set (Atlas supports the required transactions).
- Provide distinct, randomly generated `JWT_SECRET` and `JWT_REFRESH_SECRET` through the existing secret store. Do not paste them into logs, commits or chat. Access tokens last 15 minutes; new sessions have a fixed 30-day lifetime.
- Set `NODE_ENV=production` and `DEPLOYMENT_ENV=staging` for staging, with healthy TLS Redis and the proper namespace. Authentication fails closed when Redis is unavailable. Transportation limits temporarily fall back to bounded local counters.
- Apply the persistent bootstrap SES identity in Singapore. Publish its DKIM CNAME outputs for `sakaygaray.com`. Confirm domain verification, SES production sending access, sender authorization and account sending status. Configure SPF/DMARC for the domain as appropriate. SES identity creation does not itself request production sending access.
- Select SES à-la-carte pricing in the account. Do not enable dedicated IPs, tracking configuration sets or optional paid features. Application quotas are five authentication emails per address per hour, a 60-second cooldown, and 1,000 total per UTC day; failed attempts conservatively consume reservations.
- Apply the staging SES IAM policy and origin-secret/Nginx changes together. The identity lives in bootstrap so ordinary staging destruction preserves it. The old fixed `origin_header_value` variable is obsolete; the distribution and Nginx use the generated secret.
- Verify the running instance actually received the new user-data configuration. Changing Terraform user data alone does not guarantee an existing instance reruns its bootstrap script. Recreate staging with the new bootstrap, or install and test the rendered Nginx configuration through the release process. Do not deploy a mismatched CloudFront header and origin configuration.
- Set `AUTH_EMAIL_ENABLED=true` only after SES is ready. No password-only or token-exposure fallback exists. Email health uses the SES account status; provider acceptance does not guarantee inbox delivery.

## Staging sequence

1. Back up the database using the existing operational process and record the current build and configuration versions.
2. Build and test the backend and all clients. Publish the new clients in the controlled staging environment before allowing testers to sign in.
3. During a maintenance window, stop accepting old-version API traffic and disconnect old sockets. Run `node scripts/security-session-cutover.js` to inspect its dry-run description, then `node scripts/security-session-cutover.js --apply` against the explicitly selected staging environment. This creates security indexes and revokes sessions, refresh records, OTP challenges and reset links; accounts and transportation records are preserved.
4. Start only the secured API/worker versions. Verify health/readiness, Redis availability, rate-limit behavior and trusted viewer IPs through CloudFront. Confirm direct-origin requests and forged origin headers are rejected.
5. With designated test accounts, verify admin email OTP, resend/expiry, wrong-code handling, password reset and fresh login. Confirm the masked email belongs to the stored account. Check SES delivery/bounce outcomes without logging codes or reset links.
6. Verify passenger/driver login, pickup, boarding, completion and live tracking. Confirm token refresh reconnects sockets, suspension/logout removes access, duplicate refresh requests cannot create two replacements, and destination overrides cannot alter booked fares.
7. Verify the reset page at `https://api.sakaygaray.com/reset-password`. Reset tokens are carried in the URL fragment and removed from the address bar; no third-party resources load. Never change the template to use logged query tokens.

## Monitoring and rollback

Monitor 401/403/429/503 rates, Redis health, OTP/reset delivery failures, SES send counts/bounces/complaints, socket disconnects and authentication database latency. Investigate unexpected login failures before admitting more testers. The daily send cap is an application cap, not an AWS billing guarantee for other senders in the account.

If release verification fails, remain in maintenance mode or roll forward with a correction. Do not restore the old password-only admin path, old signing keys, pre-cutover refresh records, or a verifier that accepts legacy tokens. A rollback build must retain the new token/session verification and revocation behavior.

## Compatibility and remaining limitations

- Admin start/verify paths are unchanged; responses use `maskedEmail` and `resendAfterSeconds`. SMS/phone enrollment is removed from this login flow.
- Matching email addresses no longer silently link social accounts. Users must use their established sign-in method.
- Password recovery requires a local-password account. Google users continue through Google.
- Viewing legal drafts does not record policy acceptance. ETA ambiguity on overlapping/looping routes is separate from this repair.
- Concurrent refresh is strict single-use. A lost successful refresh response can require a new sign-in; clients do not replay mutations automatically.
- Local test results cannot certify the deployed CloudFront/SES configuration or real ride behavior. Record staging verification separately before calling the rollout complete.
