# Developing Glance

## Toolchain and checks

Use macOS 27 or later with Xcode/Command Line Tools providing Swift 6.4 and the
macOS 27 SDK. The main package has no third-party runtime packages.

```bash
swift test -Xswiftc -warnings-as-errors -Xcc -Werror
swift -swift-version 6 Scripts/test-packaging.swift
bash Scripts/test-release-guards.sh
swift run --package-path BuildTools swiftformat --lint . --swiftversion 6
bash Scripts/build-apps.sh
```

`BuildTools/` pins SwiftFormat separately from the apps. The formatting baseline
deliberately covers indentation, trailing whitespace, final newlines and repeated
blank lines rather than rewriting the entire code style.

Run the optional real-hardware smoke test only on a supported Mac:

```bash
GLANCE_TEST_HARDWARE=1 swift test --filter localHardwareBridgeDecodesExpectedLiveReadings
```

## Build identity and assets

`VERSION` is the shared marketing version. Normal builds derive the numeric build
from Git's commit count; CI can supply `GLANCE_BUILD_NUMBER`. `GlanceSourceRevision`
records the commit plus a dirty marker, and `GlanceBuildDate` records UTC build
time. Source archives without Git metadata are explicitly marked `unversioned`.
Both apps expose these values in an About submenu, without creating a retained
About/settings window.

Generate the original app icons with:

```bash
swift -swift-version 6 Scripts/generate-icons.swift
```

Commit the generated `Assets/` files alongside the generator. Ordinary builds
copy the icons rather than regenerating them. No SF Symbols or third-party
artwork are used in the app icons.

Public UI previews live in `Assets/Previews/`. They were rendered from the actual
views in an isolated Debug source copy, using synthetic sensor histories,
generic process rows, temporary clock settings, a fixed example date and UTC.
Only app-owned content was rasterized; menu backgrounds were flattened onto a
neutral canvas. No desktop, notifications or other applications were captured.
The capture-only instrumentation is not part of the shipping source or bundles.

When replacing previews, inspect every image and representative animation frames
for private data, clipping and legibility. Do not capture the lifecycle harness
unchanged: its process-list checks intentionally read real processes.

## Duplicate-instance ownership

The entry point acquires a per-bundle `flock` before creating models or reading
settings. `O_CLOEXEC` prevents subprocesses from inheriting the lock, and
`O_NOFOLLOW` rejects lock-file symlinks. Monitor and Time have distinct identities
and can run together. Do not elect the oldest app by comparing PIDs or delete a
live lock file; PID wraparound and inode replacement make those approaches unsafe.

## Isolated UI lifecycle smoke tests

On an interactive macOS desktop:

```bash
bash Scripts/run-ui-smoke-tests.sh
```

The script builds Debug copies under `build/smoke/` with `.smoke` bundle IDs.
They use temporary settings/lock directories and synthetic sensor snapshots.
Monitor opens its native overview and exercises detail-controller callbacks,
local graph rasterization, actual asynchronous process rows and graph teardown.
Time exercises menu creation/teardown, the separate city picker,
and fixture clock persistence. Failures produce a nonzero exit status, and a
success marker is required for each process.

These are lifecycle checks, not a claim that physical pointer clicks, every
keyboard interaction or visual appearance has been fully automated. The harness
is compiled out of Release builds. It does not need screen capture or
Accessibility access, and does not stop installed copies. Avoid interacting with
its temporary menus while it runs.

Native menu loops are entered from run-loop callbacks, not while blocking a
MainActor task, so asynchronous menu work can execute during tracking.

## CI

The Tests workflow uses GitHub's hosted `xcode-27` image (macOS 27) for strict
tests, packaging, lint and both app builds. It has read-only repository permission
and does not persist checkout credentials. UI smoke testing is an optional manual
workflow input because it needs an interactive desktop.

The workflows become active only after a GitHub repository exists and these
files are pushed. Adding them locally does not create a repository or run CI.

## Verified release preparation

From a clean checkout, with a matching version tag (a same-named branch does not
qualify):

```bash
GLANCE_RELEASE_TAG=v1.0.0 bash Scripts/package-release.sh
```

This builds both apps from fresh staging, verifies their signatures, creates
separate ZIPs, extracts and checks the payloads/notices, and writes/verifies
`SHA256SUMS.txt`. Existing artifact destinations are not overwritten.
The checkout and tag must still point to the original commit after building.

For local testing of uncommitted changes only:

```bash
GLANCE_ALLOW_DIRTY_RELEASE=1 bash Scripts/package-release.sh
```

Developer artifacts receive a `-dev` suffix and are not publishable release
candidates. Neither command creates tags or uploads files.

The manual draft-release workflow checks out an existing version tag and creates
or updates a GitHub **draft**, never an automatically published release. It
refuses to overwrite a published release. Review its output before publishing.
No Apple developer account, notarization, custom keychain, Sparkle appcast or
library-validation exception is involved.

Ad-hoc signatures and SHA-256 checksums do not establish an Apple-trusted
publisher identity or remove macOS download/quarantine restrictions.
