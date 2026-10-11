# Road-scaled jeep markers and waiting reminder

The Passenger, Driver and Admin fleet maps use `packages/parago_map_ui` for one top-view jeep symbol. The Driver live-map screen uses the same symbol. Its GPS point is at the center; selecting a jeep no longer moves the symbol downward to make room for a label. Selection uses an outline, with details available through the existing screens and tooltip. Heading is applied when available. Admin stale/offline colors and low-zoom fleet grouping remain.

The display width uses Web Mercator ground resolution at the current latitude and zoom, with an eight-metre nominal road footprint. It grows and shrinks with zoom, bounded to 8–48 logical pixels for visibility. This is a display footprint, not the jeep's physical width or an exact measurement of every road in the raster map tiles. GPS coordinates, ordering, boarding and drop-off calculations are unchanged. The marker retains a separate tap area.

The Driver map draws the jeep above other pins so a terminal marker at the same coordinate cannot hide it.

While a booking is pending or acknowledged and the passenger has no onboard ride, the Passenger app watches fresh GPS readings in the foreground. The first reliable reading for that booking establishes a waiting location. Moving more than 100 metres from it, or above 15 km/h, must persist across three distinct observations over at least ten seconds before a glass card asks `Still waiting?`.

Waiting bookings use the five-second location refresh rate. Pending version 2 bookings also upload GPS for automatic boarding; they no longer depend on the removed driver acknowledgement step to start location reporting. Legacy pending bookings are monitored for the reminder while their original boarding behavior remains.

Readings must be no older than fifteen seconds, with accuracy within thirty metres. Duplicates do not advance the check. A gap longer than fifteen seconds or an unreliable sample resets the movement window. The distance check subtracts the reported accuracy radius. A conservative speed estimate from consecutive readings subtracts both accuracy radii and supplements device speed, including browsers that report zero when speed is unavailable. Being within fifty metres of the assigned jeep with fresh jeep GPS suppresses the reminder so normal boarding is not interrupted.

`Waiting` keeps the booking and its pickup point, sets the current location as the new movement reference, and suppresses repeat reminders for sixty seconds. `Cancel` uses the existing authenticated cancellation API. The prompt disappears when the booking ends, expires or boards. It does not automatically cancel or reassign bookings, prove that another vehicle was boarded, or pause backend boarding. Legacy manual completion and Driver correction controls remain available.

The reminder requires the app to be running and receiving reliable location updates. Real-phone background behavior and deployed staging acceptance remain separate from local web and widget testing. No live data or deployment is changed by this update.

Evidence: [local review](../artifacts/road_markers_waiting_2026-10-11/REPORT.md).
