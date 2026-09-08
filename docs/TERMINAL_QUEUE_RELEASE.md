# Terminal queue repair: implementation and release

## Operating rules

Drivers self-check in without GPS. Each route/direction has one loading jeep. Waiting jeeps are promoted automatically when the loading position becomes vacant; an ineligible waiting jeep is bypassed until eligible. A full loading jeep keeps its position until explicit departure or skip. Waiting jeeps cannot reserve passengers in advance.

Departure switches the same active trip to route mode; it does not complete onboard rides. Terminal boarding requires driver acknowledgement, an explicit passenger action, and fresh passenger/vehicle GPS within the existing automatic-boarding proximity threshold. Terminal proximity-only boarding and roadside pass-by expiry are disabled.

Terminal GPS is advisory. Closing the app does not remove a waiting/loading jeep. Drivers/admins explicitly skip an unavailable jeep. Restoring places it at the back. Route-mode five-minute inactivity handling resumes after departure, with five minutes of grace.

Skip/departure converts unexpired, unboarded bookings into transfer offers. Offers reserve no seats. Accepting reserves the current loading jeep transactionally; a full/unavailable jeep leaves the offer pending. The booking ID, destination, fare and original expiry remain unchanged. Declining cancels the booking. Already boarded passengers never transfer.

## Interfaces and consistency

- Existing `POST /trips` with `operatingMode=terminal_queue` performs self check-in. `PATCH /trips/:id/start` handles legacy scheduled terminal entries. Both require a client-generated `requestId`.
- `PATCH /trips/:id/terminal/:action` supports assigned-driver/admin departure, skip and restore. Admin reorder/status/skip paths remain available; loading is automatic, so the status path accepts departure only.
- Queue mutations require `requestId`; admin actions also require a nonempty reason (maximum 500 characters). Actions are recorded with actor, trip, route and timestamp. Reusing the same action ID does not repeat its mutation.
- `POST /pickup-requests/:id/transfer/accept` and `/decline` require the current `offerId` and the owning passenger session.
- Trip responses include `terminalSummary`: queue position, reserved/onboard/free seats, last vehicle location time and a GPS warning. Seat summaries are for display; transactions decide availability.
- A route queue document serializes membership, promotion, ordering and reservations. Database indexes additionally prevent duplicate active driver/vehicle queue entries and multiple loading jeeps.
- Trip writes serialize boarding/occupancy with departure and reservations. Completing a terminal trip releases the loading position and promotes its successor, while using the existing trip-completion cleanup.
- Notifications are stored for transfer offers inside the transaction. Operations events are published after commit; reconnection reloads authoritative records. Event delivery failure does not roll back a committed queue change.

## Migration and rollout

1. Back up staging and stop API/worker writes for the maintenance window. Preserve the earlier security cutover protections.
2. Run `node scripts/terminal-queue-migration.js` against the explicitly selected environment. It defaults to read-only inspection, with automatic index/collection creation disabled.
3. Resolve every reported duplicate driver/vehicle, duplicate position, multiple-loading or ambiguous-state conflict through review. The script refuses to apply when conflicts remain. It does not guess which bookings or rides to discard.
4. Run `node scripts/terminal-queue-migration.js --apply` only after review. This backfills persistent queue counters, clears obsolete terminal inactivity pauses, sets acceptance according to loading status, and creates queue/action indexes. It does not expire bookings or end passenger rides.
5. Publish matching clients and start the updated API/worker together. Legacy queue mutations without action IDs are rejected. Verify automatic promotion on startup/scheduler reconciliation.
6. With controlled accounts, check in two jeeps without GPS, reserve the loading jeep to capacity, board explicitly with fresh GPS, depart with both onboard and unboarded passengers, accept/decline transfers, skip/restore, reorder waiting jeeps and reconnect each client.
7. Confirm route pickups and end-trip cleanup still work after terminal departure. Inspect audit actions, conflict responses, transfer notifications and seat counts before admitting testers.

No deployment, real-environment migration, or staging walkthrough was performed during local implementation. These remain separate release actions.

## Rollback and outstanding gates

Keep writes stopped if staging validation fails. Prefer a correction forward. Any rollback build must understand transfer offers and retain queue serialization, reservation limits, session revocation and legacy-token rejection. Never restore the old terminal handlers against new queue data.

The previously identified screenshot baselines and AWS deployment-scaffold assertion remain separate release checks. Local service/model tests do not replace actual web/mobile navigation, GPS and reconnect walkthroughs in staging.
