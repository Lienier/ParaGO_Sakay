# Phase 9 Proxy, Rate Limit, and Deployment Hardening

Recorded: 2026-08-02

## Safety Status

Phase 9 application hardening, deployment templates, and isolated automated
tests are complete. Nothing in this phase was deployed to DigitalOcean or AWS.
No production environment variable, firewall, database, Valkey keyspace, APK,
or admin build was changed.

The Nginx and systemd files are reviewed templates. Their live HTTPS,
WebSocket, file-permission, non-root, and graceful-restart behavior must be
demonstrated in the isolated Phase 10 staging environment before production
use.

## Proxy And HTTP Boundary

Express now trusts exactly one reverse-proxy hop and disables
`X-Powered-By`. Helmet supplies API security headers. Both JSON and URL-encoded
request bodies are limited to 1 MB.

The Nginx template provides:

- HTTP-to-HTTPS redirection.
- TLS 1.2 and 1.3.
- WebSocket upgrade handling at `/socket.io/`.
- A 1 MB request-body limit.
- Bounded connect, read, send, and client-body timeouts.
- Forwarded headers overwritten from the direct client address rather than
  appended from an untrusted chain.
- HSTS, content-type, and referrer headers.

The placeholder server name and certificate paths must be replaced before
installation. DigitalOcean App Platform uses its managed ingress instead of
this Nginx file; equivalent behavior will be checked in Phase 10. The template
is intended for the later EC2 deployment.

## CORS

Production startup now fails closed when `CORS_ALLOWED_ORIGINS` is empty or
contains `*`. Configured web origins are matched exactly. Originless mobile
requests remain allowed because Android and iOS API clients do not send a web
`Origin` header.

Before staging deployment, `CORS_ALLOWED_ORIGINS` must list the exact admin web
origins used in that environment. No origin values are hard-coded into source.

## Rate Limits

All API route groups are rate limited. The previous unrestricted driver and
passenger location exemptions were removed.

| Group | Default requests/minute | Identity |
| --- | ---: | --- |
| Authentication | 30 | Hashed client address |
| Driver location | 120 | Verified access-token subject |
| Passenger location | 30 | Verified access-token subject |
| Passenger ETA | 12 | Verified access-token subject |
| Support | 60 | Verified access-token subject |
| Admin/report/operations | 120 | Verified access-token subject |
| General APIs | 300 | Verified access-token subject |

Requests with missing or invalid tokens use a hashed client-address fallback
and are still rejected by normal authentication. Tokens, raw IP addresses,
credentials, and location values are not used as visible rate-limit keys.

The limits can be adjusted through environment variables for controlled load
testing, but malformed or non-positive values prevent startup.

## Health And Logging

`/health` and `/api/v1/health` report process liveness without dependency or
secret details. `/ready` and `/api/v1/ready` report only healthy, unhealthy, or
disabled state for MongoDB and Redis and return HTTP 503 when a required
dependency is unavailable.

Every request receives a validated or server-generated `X-Request-Id`.
Production-compatible HTTP logs are structured JSON containing only request
ID, method, path without query parameters, status, duration, and timestamp.
They exclude headers, authorization tokens, request/response bodies, query
values, and exact passenger coordinates.

Unknown-route responses also use the query-free request path. This prevents a
legacy query token or location value from being echoed by a 404 response.

## Graceful Shutdown

API and worker startup are import-safe and expose testable runtime entry
points. SIGTERM and SIGINT handling is idempotent and bounded by a default
15-second shutdown timeout.

API shutdown:

1. Stops compatibility schedulers.
2. Stops accepting HTTP connections.
3. Flushes and stops route batching.
4. Closes Socket.IO and the Redis event subscriber.
5. Closes Redis and MongoDB.

Worker shutdown:

1. Stops timers and new queue polling.
2. Waits for active location, automation, and scheduler work.
3. Flushes the latest pending locations.
4. Closes Redis and MongoDB.

Terminal queue work remains durable in Redis if it cannot be consumed before
shutdown. A timeout exits unsuccessfully so the process manager can record and
restart the failed shutdown rather than falsely reporting success.

## Process Isolation

The systemd templates run API and worker as the dedicated `parago` user with:

- `NoNewPrivileges=true`.
- Read-only system protection.
- Protected home and kernel settings.
- Private temporary storage.
- Restrictive file-creation permissions through `UMask=0077`.
- Separate API and worker job-ownership flags.

The shared environment file is expected at `/etc/parago/parago.env` and must be
owned by root with mode `0600`. Secrets and signing material remain outside the
repository.

## Automated Evidence

The ten focused deployment-hardening tests prove:

- Exactly one trusted proxy hop.
- Security headers and validated request IDs.
- 1 MB request-size rejection.
- Query-secret redaction from logs and 404 responses.
- Exact CORS allowlisting and production fail-closed behavior.
- Independent authenticated quotas for two users sharing one carrier IP.
- Ordered, idempotent, and bounded graceful shutdown.
- Static Nginx WebSocket/header/body-limit controls.
- Non-root systemd process controls.

The worker suite additionally proves shutdown waits for active work and flushes
pending locations.

The final backend regression run passed:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Integration, characterization, worker, and hardening tests | 68 | 0 |
| Total | 130 | 0 |

No test connects to production MongoDB or managed Valkey.

## Deployment Boundary

Phase 9 remains local. Phase 10 must provide live evidence for:

- DigitalOcean HTTPS and WebSocket forwarding.
- Exact staging CORS origins.
- Shared-IP limits through the real proxy.
- Graceful API and worker restart behavior.
- Secret and environment-file permissions where the hosting model permits.
- Request IDs and redacted logs under load.

Production deployment remains prohibited until Phase 10 passes and receives
explicit approval.
