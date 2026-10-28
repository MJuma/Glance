# Glance

<p>
  <img src="Assets/GlanceMonitor.png" alt="Glance Monitor app icon" width="96">
  <img src="Assets/GlanceTime.png" alt="Glance Time app icon" width="96">
</p>

Native macOS menu-bar apps.

| App | Features |
|---|---|
| **Glance Monitor** | Memory pressure and breakdown, thermal pressure, CPU/GPU/battery temperatures, fan speed, history graphs, and top processes |
| **Glance Time** | World clocks, multi time zone scrubbing and a calendar |

## Previews

### Glance Monitor

| Thermal details | Memory details |
|---|---|
| <img src="Assets/Previews/monitor-thermal.png" alt="Thermal details with CPU, GPU and battery temperatures, fan speed, pressure history and example processes" width="300"> | <img src="Assets/Previews/monitor-memory.png" alt="Memory details with RAM breakdown, example processes and a ten-minute usage graph" width="320"> |

### Glance Time

| World clocks and calendar | Time scrubbing |
|---|---|
| <img src="Assets/Previews/time.png" alt="World clocks for New York, Berlin and Tokyo above the October calendar, with time scrubbing and inline clock controls" width="360"> | <img src="Assets/Previews/time-scrubbing.gif" alt="The time scrubber moves forward, updating all three clocks and their day/night indicators, then returns to the current time on release" width="360"> |

## Requirements

- macOS 27 or later

## Download

Download either app from [GitHub Releases](https://github.com/MJuma/Glance/releases).

Extract the ZIP and move the app to `~/Applications`.

The apps are ad-hoc signed, not Developer ID-signed or notarized. macOS Gatekeeper
may block downloaded copies; follow macOS trust prompts and your device's policies,
or build locally from source. SHA-256 checksums accompany each release.

## Build

```bash
swift test
swift -swift-version 6 Scripts/test-packaging.swift
bash Scripts/test-release-guards.sh
bash Scripts/build-apps.sh
```

The script produces two self-contained, locally ad-hoc-signed bundles:

```text
build/Glance Monitor.app
build/Glance Time.app
```

Launch the bundles rather than the bare executables:

```bash
open "build/Glance Monitor.app"
open "build/Glance Time.app"
```

## Install and remove

Build from source as above, then copy whichever app you want to `~/Applications`
using Finder. Quit an existing copy before replacing it, and launch the installed
bundle rather than its executable. Each app can be installed and removed
independently.

To start an app at login, add its installed bundle to macOS Login Items. Glance
does not register login items automatically. Avoid registering both the build
copy and an installed copy.

To uninstall, quit the app, remove its login item if present, and delete its
bundle. Saved world clocks at `~/.config/glance-clocks.json` and app preferences
are intentionally left in place. Monitor's sampled histories exist only in
memory and do not require disk cleanup.

For downloaded copies, follow macOS's normal trust prompts and your device's
policies; the project does not disable Gatekeeper or remove quarantine flags.
Building locally does not require an Apple developer account.

## Local settings

| Location | Purpose |
|---|---|
| `~/.config/glance-clocks.json` | Saved clocks; preserves settings from previous local installations |
| `com.local.glance.monitor` preferences | Independent Monitor app preferences |
| `com.local.glance.time` preferences | Independent Time app preferences |

No user configuration files are included in this repository.

## Source layout

```text
Apps/GlanceMonitor/   Monitor app, system sensors, and graphs
Apps/GlanceTime/      Time app, clock model, original scrubber, unified calendar
Shared/              Small AppKit helpers and the sparkline buffer
Platform/            SDK-checked C bindings and isolated AppleSMC wire format
Tests/               Automated checks
Scripts/             Local app-bundle packaging
BuildTools/          Developer-only formatter, excluded from app dependencies
Assets/              Original generated app icons
```

## Development and release preparation

See [DEVELOPMENT.md](DEVELOPMENT.md) for strict checks, isolated Debug lifecycle
smoke tests, CI, icon generation, build identity and verified release archives.
Release tooling creates separate app ZIPs and SHA-256 checksums; the optional
GitHub workflow prepares drafts only. It does not add an app updater or require
an Apple developer account.

## License and acknowledgements

Glance is licensed under the [MIT License](LICENSE). See
[third-party acknowledgements and notices](THIRD_PARTY_NOTICES.md) for the
projects referenced by the original generic implementation. Their notices are
also included in packaged apps.

Glance is an independent project; these acknowledgements do not imply affiliation
with or endorsement by the referenced projects.
