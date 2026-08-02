# Phase 10 DigitalOcean Staging And Capacity Validation

Recorded: 2026-08-02

## Current Status

Phase 10 local preparation is complete. No staging app has been provisioned and
no production resource, database, application, deployment, or credential has
been changed. The existing managed Valkey remains online under the Phase 6
approval.

Deployment is paused for the required cost and credential-transfer checkpoint.

## Verified Existing Infrastructure

| Resource | Verified state |
| --- | --- |
| Production App Platform app | One existing app in Singapore; unchanged |
| Isolated Phase 10 app | Not yet created |
| Staging Atlas | Separate AWS Singapore free cluster, `parago_staging` only |
| Managed Valkey | Singapore, Valkey 8, 1 vCPU/1 GB, one node, online |
| Staging Redis namespace | Reserved as `parago:staging:phase10:v1` |

The known production App Platform hostname is hard-coded into the load-test
safety denylist. Remote load-test targets must also contain `staging` in the
hostname.

## Proposed Incremental App Cost

Current prices were obtained from the authenticated DigitalOcean account on
2026-08-02:

| Component | Size | Monthly rate |
| --- | --- | ---: |
| API | Shared 1 vCPU, 1 GB fixed | USD 10 |
| Worker | Shared 1 vCPU, 0.5 GB | USD 5 |
| Dedicated public egress | Two app-specific static IPs | USD 25 |
| Phase 10 app total | Two components and static egress | USD 40/month, prorated |

The existing managed Valkey costs approximately USD 15/month and is already
running. Staging Atlas is free. Large tests make no Google Routes calls. A small
live Google test remains a separate budget approval.

## Deployment Boundary

The ignored local app spec defines:

- App name `parago-capacity-staging` in Singapore.
- One API process and one worker process.
- Source branch `realtime-capacity-remediation` with deploy-on-push disabled.
- Staging Atlas URI and staging JWT secrets only.
- Existing Valkey attached by cluster name through its public TLS bindable URL,
  restricted by the managed database's staging-app trusted-source rule.
- Dedicated app egress enabled so only two stable staging IPs need Atlas access.
- Async location processing enabled.
- API schedulers disabled and worker schedulers enabled only in the worker.
- Firebase, SMS, TomTom, and Google credentials disabled.
- Exact non-production CORS placeholder until a staging admin origin exists.
- CPU and memory alerts at the Phase 10 acceptance limits.

The secret-bearing spec is stored under `.secure-backups` and excluded from
Git. DigitalOcean remote validation was not attempted because validation would
transmit those staging secrets. Explicit approval is required before app
creation performs that transfer.

## Added Test Tooling

- `scripts/prepare-phase10-load-data.js` creates up to 200 distinct synthetic
  drivers and 1,000 synthetic passengers, with defaults of 100 and 500.
- The fixture generator rejects a production URI, requires the exact
  `parago_staging` database on a separate Atlas host, and stores 12-hour test
  tokens only in `.secure-backups`.
- `load-tests/k6/rest-capacity.js` measures driver location and ordinary API
  latency and error rate.
- `load-tests/socket-capacity.js` measures connection, subscription, route-batch
  delivery, sequence regressions, reconnects, and cross-route leakage.
- `scripts/summarize-phase10-results.js` compiles machine-readable acceptance
  evidence while leaving infrastructure metrics explicitly unresolved until
  DigitalOcean telemetry is collected.
- Live Google traffic is disabled unless both `ALLOW_LIVE_GOOGLE=true` and
  `GOOGLE_BUDGET_APPROVED=true` are explicitly supplied.

All generated raw summaries are written under ignored `artifacts/phase10`.

## Planned Execution Order

1. Commit and push the reviewed remediation branch without DevTools settings,
   environment files, credentials, generated tokens, or test artifacts.
2. Create the isolated DigitalOcean staging app after cost and staging-secret
   transfer approval.
3. Add the staging app as a trusted Valkey source while retaining the existing
   production app rule.
4. Allow the two dedicated staging egress addresses in staging Atlas only.
   If the initial application cannot become active before Atlas is configured,
   deploy the generated egress-bootstrap spec first. It runs only a minimal
   health server and idle worker, accesses no database, and is replaced by the
   real spec immediately after the IPs are allowlisted.
5. Run readiness, HTTPS, WebSocket, CORS, security-header, redaction, and process
   isolation smoke tests.
6. Prepare synthetic fixtures and install k6 locally.
7. Run 5/20, 20/100, 50/200, and 100/500 progressive profiles. Stop immediately
   when an acceptance threshold fails.
8. Run the two-hour 50/200 soak only after the progressive target passes.
9. Run controlled Valkey outage, MongoDB delay, worker restart, API restart, and
   socket reconnect scenarios. Restore every dependency after each scenario.
10. Run a separately approved small live Google validation.
11. Compile raw scripts, result files, graphs, maximum validated capacity, and
    limitations for the Phase 10 approval checkpoint.

## Mandatory Stops

Testing stops if staging contacts production, cross-route delivery is observed,
Google could incur unapproved charges, Atlas or App Platform cost changes, or
any acceptance threshold fails. Production deployment remains prohibited.

## Local Evidence

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Integration, characterization, hardening, and load-tool tests | 75 | 0 |
| Total | 137 | 0 |

The seven focused Phase 10 tests prove URL denial, fixture bounds, unique
synthetic identities, Socket.IO summary behavior, live-Google interlocks,
DigitalOcean staging isolation, and fail-closed capacity reporting.

`git diff --check` also passes. `k6` is not yet installed on the workstation.
