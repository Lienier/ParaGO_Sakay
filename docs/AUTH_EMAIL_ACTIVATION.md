# SakayGaray email activation

SES region: ap-southeast-1 (Singapore).
Sender: SakayGaray <no-reply@sakaygaray.com>.

SES domain verification and DKIM are both SUCCESS, confirmed through the AWS API on 2026-09-08. Production access remains disabled. The API still reports DENIED for case 178882864700452; the support message requested more information, and the user submitted a reply. This status does not establish whether that reply has been reviewed. The staging EC2 SES permissions match Terraform. Bounce and complaint suppression are enabled at account level.

## Completed DNS configuration

These three CNAME records have been published in Namecheap and verified by SES. Retain them; no further DNS edits are needed for DKIM.

| Type | Host | Value | TTL |
| --- | --- | --- | --- |
| CNAME | `rxygos3lt724hcjuu3eydclb3gw3jitf._domainkey` | `rxygos3lt724hcjuu3eydclb3gw3jitf.dkim.amazonses.com` | Automatic |
| CNAME | `ov5ag5yqpnsvvjruhc75pvbl6ljqbuuq._domainkey` | `ov5ag5yqpnsvvjruhc75pvbl6ljqbuuq.dkim.amazonses.com` | Automatic |
| CNAME | `kf3ryh5qml77tubzcobzky2gl2thfxpp._domainkey` | `kf3ryh5qml77tubzcobzky2gl2thfxpp.dkim.amazonses.com` | Automatic |

Namecheap appends sakaygaray.com to the Host field; enter only the host shown above.

## Remaining activation gates

Rechecked directly through AWS on 2026-09-09: `ProductionAccessEnabled=false`, `SendingEnabled=true`, review status `DENIED`, case `178882864700452`. Domain verified-for-sending is true and DKIM is SUCCESS. SendingEnabled does not remove sandbox restrictions. No controlled OTP email was sent during this check; normal production OTP delivery is still blocked by the SES readiness gate.

1. Completed: SES identity verification and DKIM both succeed.
2. Confirm SES production access is approved (submission is not approval).
3. Check the deployed AUTH_EMAIL_ENABLED flag and enable it only after readiness is confirmed; restart API and worker when changing runtime configuration.
4. Perform an authorized controlled admin OTP and password-reset delivery test. Never record codes, reset tokens, or passwords in this document.

The user selected the existing admin account email as the controlled test recipient. No real test email has been sent yet. Do not weaken the SES readiness guard or fall back to password-only admin login.
