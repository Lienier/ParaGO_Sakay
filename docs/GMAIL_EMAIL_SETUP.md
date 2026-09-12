# Gmail authentication email setup

Prepared locally. Live delivery is NOT verified; SES remains the deployed provider until a separate release.

1. From the repository root, run `python tools/configure_gmail_email.py` interactively. Enter the Google App Password only at its hidden prompt. It writes `.env.gmail`, ignored by Git. This file contains a plaintext secret: do not share it, include it in archives, or publish it. This workspace is under OneDrive, so its sync policy also applies. Delete the local file when no longer needed and revoke the App Password if exposed.
2. A connection-only check (does not send mail):

   `node --env-file=.env --env-file=.env.gmail -e "require('./src/services/authEmail.service').ensureAuthEmailAvailable().then(()=>console.log('SMTP connection verified; delivery not tested')).catch(()=>{console.error('SMTP unavailable; check account and configuration');process.exitCode=1})"`

3. For local application testing use `node --env-file=.env --env-file=.env.gmail src/server.js` only with the intended local database/Redis environment configured. Then use the normal admin password + OTP flow. Do not bypass password verification or expose codes in logs. Confirm the received code verifies, resend invalidates the previous code and reset links work. SMTP acceptance alone does not prove inbox delivery.
4. For deployment, put AUTH_EMAIL_PROVIDER=gmail, AUTH_EMAIL_ENABLED=true, SMTP_USER=sakaygaray.notifications@gmail.com and SMTP_APP_PASSWORD in the existing backend secret configuration. Do not add the secret to GitHub workflow YAML, Vercel frontend settings, Flutter defines or APKs. Restart API and worker using the usual release procedure, then perform a controlled admin test. No deployment was performed by this setup.

Sender: SakayGaray <sakaygaray.notifications@gmail.com>. Gmail does not use the unverified no-reply domain alias in this setup. The provider has its own quotas, which may be below the application's daily ceiling. Existing central authentication email limits, OTP lifetime, attempt counts and reset protection remain unchanged. Gmail is a temporary testing provider and may reject server access or throttle delivery.

Implementation uses TLS port 465, certificate validation, connection timeouts, disabled SMTP logging and disabled attachment file/URL reads. Failures remain generic 503 responses, with no fallback to another provider or password-only authentication. Omitted AUTH_EMAIL_PROVIDER retains SES behavior; unknown values fail closed.

Reference: https://nodemailer.com/smtp
