# Glance privacy

Glance Monitor and Glance Time run locally. Neither app implements analytics,
advertising, user tracking, an update checker, or runtime network requests.

## Local readings

Monitor reads macOS memory statistics, thermal state, supported temperature/fan
sensors, and process names/resource usage for its detail menus. Numeric histories
are bounded to ten minutes in memory and disappear when the app exits. Process
lists are requested only when their menus open; they are not saved to disk.

Time uses macOS timezone/calendar data and saves the clocks you choose in
`~/.config/glance-clocks.json`. Clock labels and timezone selections are not
uploaded. Removing the app does not automatically delete this file.

## Instance locks

Each app keeps a separate empty lock file under
`~/Library/Application Support/Glance/Instances/`. Kernel-held locks prevent
duplicate copies of the same app; file existence or a saved PID is not treated
as evidence that an app is running. The files contain no usage history. They can
remain after exit, with the lock released automatically by macOS.

## Diagnostics and build identity

Diagnostic messages use macOS unified logging under each app's bundle identifier.
They describe lifecycle events, failure/recovery transitions and request counts.
Error descriptions can include local paths or invalid settings; macOS logging
privacy controls apply to private interpolated fields.

About submenus show version, build number, source revision/dirty state and UTC
build time. These values are generated when building the app, not by inspecting
your source checkout or running Git during app startup.

Review diagnostics before sharing them. Do not attach private process lists,
clock files, credentials, or unrelated system logs to public issues.

## Developer tools and downloads

The developer-only formatter is fetched through Swift Package Manager. CI and
release workflows contact GitHub when explicitly used; none of those tools is
included in either app's runtime dependency graph.

Debug lifecycle smoke tests use separate bundle identifiers, temporary clock
settings and synthetic telemetry. They do not capture the screen, record audio,
request Accessibility permission, or modify your real saved clocks. They briefly
display their own menus and city picker.

Glance does not register login items automatically or disable Gatekeeper.
Follow macOS trust prompts and your device policies for downloaded copies.
