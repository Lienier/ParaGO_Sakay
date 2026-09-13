# Performance, security and resilience test preparation

Prepared 2026-09-11. Status: NOT RUN. Preparation only; this document is not evidence of a passing test or authorization to execute a campaign.

## Environment and launch gates

- Use a disposable local environment or a dedicated isolated test deployment, database, Redis namespace and synthetic accounts. The current api.sakaygaray.com deployment serves real users even though its workflow is named staging: exclude it.
- Before execution, record the exact commit, target host, database name, Redis isolation, API/worker instance counts, CPU/RAM limits, indexes and test-machine specifications. A hostname containing staging does not prove isolation.
- Verify fixture scripts against current session authentication before use. Existing token manifests may have expired or predate session security. Never bypass authentication to make load tests pass.
- Use local fake email delivery and synthetic files; no SES, Google Routes, push messages to real accounts or paid external traffic. Keep credentials and test manifests out of reports and Git.
- Install k6 for REST performance and optionally OWASP ZAP or Burp for manual security inspection before the execution window. Node dependencies are declared in package.json. No installation was performed during preparation.
- Start with one synthetic passenger and driver to verify the workload and responses. Do not treat successful /health requests as ride-flow performance evidence.
- Confirm operator, time window, cleanup scope and recovery procedure before starting. Do not run any commands below yet.

## 3.1 Performance

Reuse `load-tests/k6/rest-capacity.js`, `load-tests/socket-capacity.js` and the fixture/profile scripts documented in `load-tests/README.md`.

| Campaign | Proposed workload | Duration | Purpose |
| --- | --- | --- | --- |
| Smoke | 1 driver, 1 passenger | 1 minute | Verify credentials, fixtures and assertions |
| Baseline | 5 drivers, 20 passengers | 5 minutes | Establish latency and resource baseline |
| Expected load | 20 drivers, 100 passengers | 15 minutes | Provisional demand, to confirm before execution |
| Stress | 20/100, 50/200, 100/500 driver/passenger plateaus | 5 minutes each | Find first violated threshold; stop rather than force a crash |
| Spike | baseline, sudden 50/200, baseline | 2/1/5 minutes | Observe overload and recovery |
| Scalability | same 20/100 workload with 1 then 2 API instances | 15 minutes each | Compare throughput/latency while holding other resources constant |

The existing REST script supports constant VUs only. Stress plateaus can be separate runs; a true continuous spike requires a ramping scenario adapter before execution. Two API instances must share session and limiter state; doubling resources is not assumed to double capacity. The existing harness is not yet a complete booking/boarding/unloading workload.

Ride-flow additions required before claiming end-to-end performance coverage: independent synthetic bookings per user, valid destination/fare snapshots, fresh proximity observations, board, unload, then verify ride state and occupancy. Include terminal departure versus boarding, reservation capacity and duplicate requests. Do not loop mutations against shared fixture rides.

Capture p50/p95/p99 latency by endpoint, successful throughput, HTTP status counts (429 separately), failed business assertions, socket connection/reconnect time, event delay, worker backlog, CPU, RSS, MongoDB latency/connections and Redis latency/errors. A run dominated by limiter rejection is not successful throughput.

Proposed acceptance targets: driver location p95 <250 ms; ordinary reads p95 <500 ms; unexpected request failures <1%; socket route delivery p95 <1500 ms. These are initial targets from the existing harness, not measured promises. Record p99 without inventing a passing limit. Zero duplicate rides, excess occupancy or unauthorized events.

Stop on data-integrity violation, unexpected email/external traffic, persistent readiness failure, or unexpected failures >5% for 60 seconds. Set hardware-specific resource alarms before execution. Following overload, check readiness and baseline latency recovery for five minutes.

Future commands (only after gates pass):

```powershell
# Fixture preparation writes data; validate isolation first.
npm run phase10:fixtures
npm run phase10:profile -- --drivers=5
$env:BASE_URL='https://isolated-staging.example'
$env:DRIVER_VUS='5'
$env:PASSENGER_VUS='20'
$env:DURATION='5m'
k6 run load-tests/k6/rest-capacity.js
npm run phase10:socket -- --url=https://isolated-staging.example --passengers=20 --duration=300
```

Create the ignored artifacts/phase10 results directory before execution. Read the fixture scripts first; do not copy production account data.

## 3.2 Security

| ID | Area | Cases and required result |
| --- | --- | --- |
| SEC-01 | Authentication | Omitted/forged role, direct admin login, social login, expired OTP, resend invalidation, concurrent OTP verification; no OTP bypass or code disclosure |
| SEC-02 | Sessions | Wrong-purpose/issuer/audience tokens, concurrent refresh, logout/reset/suspension revocation; one refresh winner, revoked HTTP/socket access rejected |
| SEC-03 | Authorization | Passenger A targets B's booking; driver A targets B's trip; passenger accesses admin endpoints; reject without mutation or disclosure |
| SEC-04 | Fuzz inputs | Null, arrays instead of strings, Mongo operator objects, malformed IDs, negative/huge seat counts, NaN-like coordinates, future/old GPS, reversed/oversized report dates; controlled 4xx, no server crash or data change |
| SEC-05 | Abuse limits | Multiple instances share counters, Retry-After visible, spoofed forwarding headers rejected, Redis outage fails closed for auth |
| SEC-06 | Browser security | Inspect reset page cache/security headers, stored announcement/support content escaping, CORS and object/document access using controlled accounts |
| SEC-07 | Transport/storage | Verify HTTPS/certificate and secure WebSocket; inspect database/storage encryption configuration and backups separately; confirm keyed OTP/reset storage and password hashing without exporting secrets |
| SEC-08 | Disclosure | Redacted logs, generic recovery responses, no tokens in URLs/access logs or production errors |

Use existing `tests/security-repair.integration.test.js`, `tests/security-counters.test.js`, `tests/deployment-hardening.test.js` and `tests/realtime-capacity.characterization.test.js` first. Later command: `npm run test:security`. Add bounded fuzz cases to the isolated integration environment before using a scanner.

Manual penetration review supplements automated assertions: intercept a legitimate synthetic request, vary ownership and role, inspect both response and database effects. A scanner pass alone is not proof of security. Start ZAP/Burp with exact host scope and passive inspection; active scans require a separately confirmed isolated target. No Metasploit exploitation or unrestricted crawling is prepared.

## 3.3 Controlled failure drills

Introduce one deterministic fault at a time, not random production process termination. Record normal behavior first and restore immediately if the stop criteria are met.

| ID | Fault | Expected behavior | Recovery |
| --- | --- | --- | --- |
| CHAOS-01 | Stop isolated worker for 30 seconds | API remains responsive; backlog visible; old GPS jobs cannot board/unload later | Restart worker, check backlog drains and ride invariants |
| CHAOS-02 | Interrupt isolated Redis for 30 seconds | Auth fails closed; bounded transport fallback; no unlimited traffic | Restore Redis; verify readiness and shared limits |
| CHAOS-03 | Interrupt isolated MongoDB for 15 seconds | Writes fail clearly; no partial boarding/unloading occupancy update | Restore DB; reconcile rides and bookings before retry |
| CHAOS-04 | Lose response after successful board/unload | Client reconciliation/retry returns committed state without duplicate occupancy | Restore connection, refresh authoritative state |
| CHAOS-05 | Disable phone network, then reconnect | Clear offline state; fresh GPS required; sockets reconnect with valid session | Restore network; check no stale automatic action |
| CHAOS-06 | Make fake email/notification sender fail | No admin password-only fallback; committed unload remains successful | Restore fake sender; notification delivery remains best effort |
| CHAOS-07 | Restart one API instance during activity | Remaining instance handles eligible traffic; reconnect and revocation remain correct | Restart instance and verify readiness/session consistency |

Reuse async-worker, worker-process-controls, redis-foundation and realtime-capacity tests for controlled injected faults. No kill/stop script is included because actual isolated process identities are not yet selected. Before a drill, record exact stop/start commands for that environment, confirm they cannot target live services, and nominate a recovery operator.

## Execution order and reporting

1. Validate isolation, tooling, fixtures and observability.
2. Security regression and bounded input checks.
3. Performance smoke, baseline, expected load.
4. Stress/spike/scalability after required workload adapters exist.
5. Controlled failure drills, one fault at a time.
6. Restore environment, verify ride/account invariants and remove only campaign-owned synthetic data.

For every case record: ID, commit, environment, workload, start/end time, expected/actual result, latency/error metrics, integrity checks, redacted artifact location, failure/retest link and cleanup result. Mark unexecuted cases NOT RUN. Never interpret absent results as PASS.

Readiness remaining: choose isolated target and capacity, validate current-session fixtures, prepare continuous spike/ride-lifecycle workloads, install optional tools, configure metrics, and confirm the execution window. No tests, scanners, email sends, infrastructure changes or fault injection were started for this preparation.
