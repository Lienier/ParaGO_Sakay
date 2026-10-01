# ParaGO full system flow documentation

Updated: 2026-09-27

This folder is a new, standalone documentation set. The original diagram folders are untouched. It describes the current ParaGO implementation as found in the repository: passenger, driver, administrator, backend/API, database, realtime delivery, and external services.

## Open the diagrams

- **Editable source:** `ParaGO_full_system_flow.drawio` - open with diagrams.net / draw.io and select a page from the page list.
- **Local viewer:** `index.html` - open directly in a browser. It contains the six exported SVG sheets with tabs, a legend, and source notes.
- **SVG sheets:** the primary `end_to_end_process_map.svg` plus `system_map.svg`, `passenger_ride.svg`, `driver_terminal.svg`, `admin_operations.svg`, and `shared_exceptions.svg` files are suitable for documentation, print, and review.

## Diagram set

0. **Standard end-to-end process map** - the primary start-to-finish procedure, separated by setup, terminal dispatch, booking, ride state, and completion lanes.
1. **System map** - user roles, Flutter clients, API services, durable state, realtime delivery, AWS deployment, and external dependencies.
2. **Passenger ride lifecycle** - route selection, remote pin booking, validation, assignment, driver acknowledgement, boarding, travel, para alert, and unloading.
3. **Driver terminal-to-route operation** - terminal-intent trip, two-fix arrival, queue promotion, ten-minute loading window, explicit departure, route operation, inactivity pause, and explicit trip end.
4. **Administrator operations** - OTP login, configuration, dispatch, reports, support, announcements, account management, and the separate PC-only mobile release note.
5. **Shared services and exception paths** - authorization, transactions, idempotency, uncertain timeouts, reconciliation, GPS limitations, notifications, cache/revocation, and dependency failures.

## Symbol legend

- **Rounded rectangle:** process or user action.
- **Ellipse:** start or end.
- **Diamond:** decision or validation gate.
- **Cylinder:** persistent or shared data store.
- **Document/page:** notification or durable message.
- **Cloud:** external actor or service.
- **Note:** operational caveat or rollout boundary.
- **Arrow:** direction of control or data flow.

## Current behavior and boundaries

- MongoDB/API state is authoritative; Socket.IO and push/email notifications are delivery mechanisms. Clients reconcile after reconnect or resume.
- Passenger remote pickup pins do not require phone GPS. Actual boarding still requires the configured fresh-location/proximity checks; manual driver unloading remains available when passenger GPS is unavailable.
- Drivers start with a terminal-intent trip. Direct route start is rejected for new flows. Terminal arrival needs two ordered, fresh, accurate fixes in the configured terminal radius. Departure is explicit; the ten-minute loading timer does not auto-depart.
- A departed trip becomes route operation and can accept roadside pickups subject to capacity. Ending a trip is separate from departing the terminal.
- Group booking support exists in the code path but is **disabled by default** behind `GROUP_BOOKINGS_ENABLED=false`; the passenger sheet labels the group behavior as a gated capability.
- Existing terminal-first changes and indexes still have audit, maintenance-window, client/device, and deployment gates. This documentation is not a production-readiness claim.
- APK catalog publication is performed by the PC-only local super-admin tool, not by the admin web.

## Source references

- `docs/PARAGO_COMPLETE_SYSTEM_PROCESS_AND_CAPABILITIES.md`
- `docs/PASSENGER_BOOKING_REVISION.md`
- `docs/TERMINAL_FIRST_DRIVER_STATUS.md`
- `docs/SECURITY_REPAIR_STATUS.md`
- `src/routes/pickupRequests.routes.js`, `src/routes/boarding.routes.js`, `src/routes/stopAlerts.routes.js`, `src/routes/trips.routes.js`
- `src/services/operatingRules.service.js`, `src/services/tripLifecycle.js`, `src/services/terminalArrival.service.js`
- Flutter clients under `parago_passenger/`, `parago_mobile/`, and `parago_admin_web/`

When implementation changes, regenerate the SVG and Drawio sources with `node generate_flowcharts.js` and update this README's date and caveats.
