# Terminal Queue Management

## Purpose

Terminal queue management lets admins see active jeepneys waiting at a terminal and adjust the queue when dispatch needs to move or skip a jeepney.

## Admin UI

The admin overview dashboard includes a Terminal dispatch board with:

- Terminal queue trips, sorted by loading, waiting, skipped, then queue order.
- Waiting terminal passengers linked to active terminal queue trips.
- Route-mode drivers operating outside the terminal queue.

Each visible terminal queue trip has controls for:

- Move up.
- Move down.
- Skip this jeepney.
- Restore a skipped jeepney.

Skipped jeepneys stay visible but are sorted after waiting jeepneys.

## Backend Endpoints

Admin-only endpoints:

```http
GET /admin/hybrid-dispatch
PATCH /admin/terminal-queue/:tripId/reorder
PATCH /admin/terminal-queue/:tripId/skip
```

`PATCH /admin/terminal-queue/:tripId/reorder` accepts:

```json
{
  "direction": "up"
}
```

`direction` can be `up` or `down`.

`PATCH /admin/terminal-queue/:tripId/skip` accepts:

```json
{
  "skipped": true
}
```

Use `false` to restore the trip.

## Dispatch Behavior

- `loading` trips remain highest priority.
- `waiting` trips are next.
- `skipped` trips remain visible but are not selected for new terminal passenger assignment.
- Restoring a skipped trip puts it at the back of the active terminal queue.
- If the restored trip already has acknowledged terminal passengers, it returns to `loading`; otherwise it returns to `waiting`.

## Verification

Run:

```bash
npm test
```

Relevant tests:

- `Hybrid - Terminal Queue Sorting`
- `Hybrid - Terminal Queue Status Normalization`
