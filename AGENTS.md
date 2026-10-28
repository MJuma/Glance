# Glance

Two independent macOS menu-bar applications share this repository:

- Glance Monitor: one thermal-first status item with independently colored thermal
  and memory indicators, a combined overview, and detail submenus.
- Glance Time: world clocks, time scrubber, and calendar.

## Build and test

```bash
swift test
bash Scripts/build-apps.sh
```

Packaged apps are written to `build/Glance Monitor.app` and `build/Glance Time.app`.
Launch the bundles, not the bare SwiftPM executables.

## Boundaries

- `Apps/GlanceMonitor` must not depend on clock/calendar functionality.
- `Apps/GlanceTime` must not initialize hardware monitors or background networking.
- `Shared` contains only genuinely shared AppKit helpers and small value types.
- Keep user settings, local history, browser profiles, and compiled products out of Git.
- No remote services are required by either app.

## Conventions

Use AppKit for the application shell, status items, and Monitor's detail views.
Monitor must not import or link SwiftUI. Time embeds SwiftUI lazily in its menu
and city picker.
Keep polling inexpensive and timers tolerant.
Do not treat saved configuration as proof of live operating-system state.
Surface action failures in the UI and log diagnostic failures without sensitive data.

Monitor records memory pressure by value with each ten-second sample. Its native
AppKit memory graph uses total physical RAM as a fixed scale and retains at most
ten minutes (121 samples including rapid manual refreshes). Unreadable pressure
is unknown, not inferred from utilization.

Release detail-menu graph views after tracking ends, and release Time's hosting
view/controller when its menu/picker closes. Keep icon redraws separate from model polling.

Require macOS 27 and Swift 6 language mode. Use resolution-independent NSImage
drawing handlers, not lockFocus. Both apps use a real NSMenu for system-managed
tracking. Time must end menu tracking before opening the city picker, so mouse
and keyboard input reach it. Do not add manual event monitors or older-system
fallbacks. Preserve clock configuration compatibility and report
persistence errors without overwriting unreadable settings.

Keep undocumented hardware details in HardwareTelemetry.swift and Platform/.
Import SDK C declarations through GlancePlatform, never @_silgen_name. Failed
readings must remain unavailable/unknown, with failure/recovery diagnostics.
Load process lists asynchronously on menu open and cancel them on close; never
block the main actor waiting for a subprocess or add process-list idle polling.

Preserve the MIT license and third-party notices. Include both LICENSE and
THIRD_PARTY_NOTICES.md in each distributed app bundle.
