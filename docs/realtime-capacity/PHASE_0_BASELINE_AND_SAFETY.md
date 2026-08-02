# Phase 0 Baseline and Safety Boundary

Recorded: 2026-07-29

## Repository Baseline

- Branch: `realtime-capacity-remediation`
- Baseline commit: `9391296f0407f2280412cd021bc7abe174f7733e`
- Node.js: `24.13.1`
- npm: `11.12.1`
- Backend package engine: Node.js `22.x`, npm `11.x`
- Pre-existing untracked files left untouched:
  - `parago_admin_web/devtools_options.yaml`
  - `parago_passenger/devtools_options.yaml`

The Flutter version probe was not used as evidence because it blocked on the
local Flutter startup lock. No existing Dart or Flutter processes were stopped.

## Automated Baseline

The root `npm test` command completed successfully:

- Backend unit tests: 62 passed, 0 failed
- Announcement integration tests: 6 passed, 0 failed
- Announcement integration tests used `mongodb-memory-server`

The existing suite does not yet provide integration coverage for location
ingestion, Socket.IO room authorization, concurrent boarding, route batching,
or worker retries. Those gaps are the focus of Phase 1.

## Public Health Baseline

Endpoint:

`https://paragosakay-app-qulmw.ondigitalocean.app/health`

Ten read-only HTTPS checks were made from the development workstation:

| Measurement | Result |
| --- | ---: |
| Successful responses | 10 of 10 |
| HTTP status | 200 |
| Average TTFB | 230.5 ms |
| Minimum TTFB | 184.2 ms |
| Maximum TTFB | 354.5 ms |
| Average total time | 230.6 ms |

This measures only public network, TLS, proxy, and process health. It does not
measure authenticated API, MongoDB, Socket.IO, Google Routes, or Flutter UI
latency.

## Redacted Environment Inventory

The local environment contains these configuration names. Values were not
printed or copied into this document:

- `BOARDING_WINDOW_MINUTES`
- `FACEBOOK_APP_TOKEN` (empty)
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`
- `FIREBASE_PROJECT_ID`
- `GOOGLE_CLIENT_IDS`
- `GOOGLE_ROUTES_API_KEY`
- `JEEP_PASS_BY_REASSIGN_METERS`
- `JWT_EXPIRES_IN`
- `JWT_REFRESH_EXPIRES_IN`
- `JWT_REFRESH_SECRET`
- `JWT_SECRET`
- `LOG_LEVEL`
- `MAX_REQUESTS_PER_PASSENGER_PER_TRIP`
- `MONGO_URI`
- `NODE_ENV`
- `ORS_API_KEY`
- `PICKUP_REQUEST_TTL_MINUTES`
- `PORT`
- `SMSAPIPH_API_KEY`
- `SMSAPIPH_BASE_URL`
- `STOP_ALERT_COOLDOWN_MINUTES`
- `TOMTOM_API_KEY`

Redis, worker-mode, proxy, and environment-namespace configuration does not
exist yet and must not be added before its implementation phase.

## Secret Audit

- `.env`, `.env*`, local DigitalOcean specifications, and trial keys are
  excluded by `.gitignore`.
- Current JWT secrets, MongoDB URI, Google Routes key, SMS API key, and Firebase
  private key values were not found in Git history.
- The history scan found the Firebase project identifier and public SMS service
  base URL. These are identifiers, not server credentials.
- Tracked Firebase client configuration contains public client identifiers.
  Their Google/Firebase restrictions still need to be verified in the provider
  console during deployment hardening.
- No secret value is included in this report.

## Current Cost Boundary

Current public prices used only for planning:

| Resource | Planning cost |
| --- | ---: |
| MongoDB Atlas Free staging cluster | USD 0/month |
| DigitalOcean managed Valkey, single 1 GiB node | Starts at USD 15/month |
| MongoDB Atlas Flex staging cluster | USD 8-30/month by usage |
| MongoDB Atlas dedicated cluster | Starts near USD 56.94/month before regional differences |

Exact Singapore availability and checkout totals must be verified in each
provider console before provisioning. No paid resource has been created during
Phase 0.

## Production Database Context

Production MongoDB Atlas details confirmed by the account owner:

- Tier: Free
- Cloud provider: AWS
- Region: Hong Kong (`ap-east-1`)
- MongoDB version: `8.0.28`
- Topology: replica set, 3 nodes
- Managed backup: inactive

The Singapore DigitalOcean backend therefore communicates with MongoDB across
regions. This is a potential latency contributor that must be measured during
later characterization; it is not treated as the sole cause without evidence.

## Verified Local Backup Tools

- MongoDB Database Tools: `100.17.0`
- `mongodump` and `mongorestore` were extracted from MongoDB's
  Authenticode-validated Windows MSI into the ignored `.tools/` directory.
- Gpg4win: `5.0.2`
- GnuPG: `2.5.18`
- AES-256 support: verified

The normal MongoDB MSI installation returned Windows Installer error `1603`.
No forced system installation was attempted. Administrative extraction of the
same signature-verified MSI succeeded instead.

## Encrypted Production Backup

The account owner explicitly approved read-only production backup access.

- Backup time: `2026-07-29T07:00:23Z`
- Source format: compressed `mongodump` archive
- Source size: `289709` bytes
- Source SHA-256:
  `1E8FF2125B9D1EFACA71BD59A03D01EB1949EB3CD030D0FA6D811B7E51C03DAB`
- Encryption: GnuPG symmetric `AES256.CFB`
- Encrypted size: `289827` bytes
- Encrypted SHA-256:
  `9E25A613EB6280CA97C46B5FDFD7B62536E333185C213B423EE8415717574E39`
- Decryption verification: passed
- Decrypted verification SHA-256 matched the source SHA-256
- Plaintext archives remaining: zero
- Diagnostic logs remaining: zero

Retained ignored files:

- `.secure-backups/parago-production-20260729T070023Z.archive.gz.gpg`
- `.secure-backups/parago-production-20260729T070023Z.archive.gz.gpg.manifest.json`

The encryption passphrase was entered through Gpg4win and was not printed,
stored in Git, or included in command output.

## Local Restore Verification

Production records were restored only into an ephemeral MongoDB bound to
localhost. They were never copied into Atlas staging.

- Restore MongoDB version: `8.0.28`, matching the dump source
- Restored collections: 20
- Restored documents: 323
- Document restore failures: zero
- Plaintext restore archives remaining: zero
- Temporary restore processes remaining: zero
- Atlas staging writes during restore: zero

The reusable verifier is
`scripts/verify-production-backup-restore.js`. It validates both encrypted and
decrypted SHA-256 hashes, refuses a non-local restore target, and removes the
temporary plaintext archive in its cleanup path.

Archived index recreation is not yet accepted as verified. `mongorestore`
restored all documents but stalled while recreating archived background
indexes, both with MongoDB 8.2.6 and with the matching MongoDB 8.0.28 binary.
The successful data-recovery verification therefore used `--noIndexRestore`.
Index definitions and query plans will be handled by the explicit dry-run/apply
migration procedure in Phase 5. This limitation must not be represented as a
full index-recovery test.

## Isolated Atlas Staging

The local staging URI is stored in ignored `.env.staging` configuration:

- Authenticated connection: verified
- Database name: `parago_staging`
- Different from the configured production URI: verified
- Initial collection count: zero
- Production records copied to staging: zero

The transaction-based synthetic seeder
`scripts/seed-staging-synthetic.js` populated:

- 13 collections
- 57 synthetic documents
- 2 synthetic routes
- 5 synthetic jeepneys and drivers
- 10 synthetic passengers
- 5 synthetic trip sessions
- Synthetic pickup, ride, support, announcement, and notification records

The post-seed provenance audit found zero non-synthetic identity, route,
vehicle, support-message, or announcement markers. Generated staging app login
credentials are retained only in ignored
`.secure-backups/staging-synthetic-accounts.json`.

The account owner supplied redacted Atlas cluster screenshots. They confirm:

| Environment | Tier | Provider and region | Version | Topology | Backup |
| --- | --- | --- | --- | --- | --- |
| Production | Free | AWS Hong Kong (`ap-east-1`) | `8.0.28` | Replica set, 3 nodes | Inactive |
| Staging | Free | AWS Singapore (`ap-southeast-1`) | `8.0.28` | Replica set, 3 nodes | Inactive |

The staging cluster is aligned with the Singapore DigitalOcean application
region, while production MongoDB remains cross-region in Hong Kong. Both Atlas
clusters currently cost USD 0/month.

## DigitalOcean App Configuration Backup

The authenticated `parago-phase0` context was used only for read operations.
After the export and provider-option queries completed, that context was
removed from local `doctl` storage. The temporary provider token must also be
revoked in the DigitalOcean control panel.

- `doctl`: `1.164.0`
- App ID: `7b385a5b-10f5-4eba-9d0a-0e73ea2a3b08`
- App name: `paragosakay-app`
- App region: Singapore (`sgp`)
- Service name: `parago-sakay`
- Service size: `apps-s-1vcpu-1gb-fixed`
- Service instances: 1
- Source branch: `main`
- Environment entries audited: 21
- Unredacted environment values in evidence copy: zero
- Known local secret matches in evidence copy: zero
- Raw plaintext app specifications remaining: zero

The raw production app specification was encrypted with GnuPG AES-256, then
decrypted once to verify its SHA-256 hash. The verification and raw plaintext
files were removed. The encrypted backup and manifest are retained in ignored
secure storage:

- `.secure-backups/digitalocean-app-spec-20260729T082855Z.json.gpg`
- `.secure-backups/digitalocean-app-spec-20260729T082855Z.json.gpg.manifest.json`

The reviewable evidence copy is
`docs/realtime-capacity/digitalocean-app-spec.redacted.json`.

## DigitalOcean Valkey Cost Candidate

The read-only provider options confirm Valkey is available in Singapore
(`sgp1`). The Phase 6 starting candidate is:

- Engine: Valkey
- Region: `sgp1`
- Plan slug: `db-s-1vcpu-1gb`
- Nodes: 1
- Published starting price: USD 15/month
- High availability: no

This is a cost-planning candidate only. No Valkey resource is created in Phase
0. Provisioning remains in Phase 6 after the cache implementation and explicit
user approval. The account owner approved this USD 15/month planning candidate
and explicitly directed that it must not be provisioned before Phase 6.

## Remaining Phase 0 Blockers

None. Phase 0 is complete.

No production migration, schema change, paid provisioning, or runtime code
change may begin until these blockers are resolved and the Phase 0 evidence is
explicitly approved.

## Phase 0 Approval Gate

Approval still requires:

1. Revoke the temporary `parago-phase0-readonly` token in the DigitalOcean
   control panel and confirm revocation.
2. Approve the complete Phase 0 evidence and explicitly authorize Phase 1.

Completed gate decisions:

- Redacted production and staging Atlas evidence: supplied
- Valkey Phase 6 planning candidate: approved, not provisioned
- Archived-index restore limitation: accepted for controlled handling in
  Phase 5
- Temporary `parago-phase0-readonly` provider token: revoked
- Phase 0 evidence: explicitly approved by the account owner
- Phase 1 characterization and regression testing: explicitly authorized

Approval recorded: 2026-07-29.
