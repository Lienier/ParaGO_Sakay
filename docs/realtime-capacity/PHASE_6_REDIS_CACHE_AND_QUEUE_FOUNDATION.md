# Phase 6 Redis Cache and Queue Foundation

Recorded: 2026-07-29

## Safety Status

Phase 6 application code, isolated tests, managed Valkey provisioning, TLS
validation, namespace validation, and firewall validation are complete.

Phase 6 code has not been deployed to production. The existing production
backend remains on its pre-cutover behavior until the later coordinated
deployment phase. No permanent ride, fare, support, announcement, account, or
trip record was moved out of MongoDB.

## Managed Service

The user-approved DigitalOcean Managed Valkey candidate was provisioned with
the following non-secret configuration:

| Property | Value |
| --- | --- |
| Name | `parago-realtime-valkey` |
| Engine | Valkey 8 |
| Region | `sgp1` |
| Plan | `db-s-1vcpu-1gb` |
| Nodes | 1 |
| Network | ParaGO App Platform VPC |
| TLS protocol | `rediss://` |
| Estimated price | USD 15/month |
| Status after creation | Online |

The cluster identifier, host, username, password, and connection URI are not
included in this report.

The database firewall permits only the ParaGO App Platform application. A
single workstation IP was temporarily allowlisted for each live validation
run and removed immediately afterward. The final firewall listing contained
only the ParaGO application rule.

## Runtime Foundation

The backend now provides:

- A single official `redis` client with bounded startup behavior.
- Mandatory `rediss://` in production.
- Environment-qualified Redis namespaces.
- Readiness output limited to configured, healthy, or unhealthy state.
- JSON cache operations that fail safely.
- Token-owned distributed locks.
- A 60-second latest-jeep-location cache.
- A 45-second driver-to-jeep/trip/route context cache.
- Targeted driver-context invalidation after assignment, trip, route, and
  status changes.
- Shared Google passenger ETA result caching and request coalescing.
- MongoDB and direct-processing fallbacks when Valkey is unavailable.

The supported environment contract is:

| Variable | Purpose |
| --- | --- |
| `REDIS_URL` | Secret TLS connection URI |
| `DEPLOYMENT_ENV` | Environment identity such as staging or production |
| `REDIS_NAMESPACE` | Environment-qualified key prefix |
| `REDIS_CONNECT_TIMEOUT_MS` | Bounded startup connection timeout |
| `REDIS_LATEST_LOCATION_TTL_SECONDS` | Latest location TTL, default 60 |
| `REDIS_ACTIVE_CONTEXT_TTL_SECONDS` | Active context TTL, default 45 |

`REDIS_NAMESPACE` must contain the active `DEPLOYMENT_ENV` whenever Redis is
configured. Staging uses `parago:staging:v1`; production will use
`parago:production:v1`.

## Live Validation

The provider-level live validation confirmed:

```json
{
  "tls": true,
  "connected": true,
  "namespacesIsolated": true,
  "ttlSeconds": {
    "staging": 60,
    "production": 60
  },
  "lockOwnership": true,
  "durationMs": 602
}
```

The ParaGO service-level live validation confirmed:

```json
{
  "connected": true,
  "health": "healthy",
  "namespace": "parago:staging:v1",
  "latestLocationCache": true,
  "activeContextCache": true,
  "activeContextInvalidation": true,
  "etaRequests": 5,
  "etaLoaderCalls": 1
}
```

Both validators delete their test keys before disconnecting. They do not print
connection details, credentials, or cached values.

After removing the temporary workstation firewall rule, the same TLS validator
timed out as expected. This proves the workstation no longer has network
access. A final firewall query returned exactly one rule: the ParaGO App
Platform trusted source.

## Automated Evidence

The complete backend suite passed after the Phase 6 changes:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Integration and characterization tests | 46 | 0 |
| Total | 108 | 0 |

The six isolated Redis foundation tests cover:

- Namespace safety.
- Latest-location TTL.
- Active-context cache and invalidation.
- MongoDB fallback and readiness during an outage.
- ETA request coalescing.
- Direct ETA fallback while Redis is unavailable.

Tests continue to use isolated in-memory MongoDB and an injected fake Redis
client. They do not connect to Atlas, DigitalOcean Valkey, or production.

## Dependency Review

The backend upgraded compatible direct dependencies and moved Firebase Admin
to version 14.2.0. The original production audit contained 25 findings,
including two critical findings. The critical findings were removed.

The remaining npm report is an upstream Google SDK tree consisting of five
moderate and seven high findings. Several are in Storage, Firestore, and
package cleanup paths ParaGO does not invoke. npm currently offers no safe,
non-breaking resolution and incorrectly proposes downgrading Firebase Admin.
No forced downgrade or unsupported transitive override was applied.

This residual must remain visible in later security reviews. It does not
justify weakening authentication or forcing incompatible packages.

## Deployment Boundary

The managed cluster is running and billable. Its connection URI has not been
added to the production App Platform environment because the Phase 6 code has
not undergone the later staging deployment and capacity gates.

During the approved deployment phase:

- Inject the private TLS URI as a secret.
- Set `DEPLOYMENT_ENV=production`.
- Set `REDIS_NAMESPACE=parago:production:v1`.
- Verify `/ready` before accepting traffic.

This prevents an infrastructure-only checkpoint from silently changing
production runtime behavior.
