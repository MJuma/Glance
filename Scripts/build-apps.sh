#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$ROOT"
CONFIGURATION="${GLANCE_CONFIGURATION:-release}"
SMOKE_BUILD="${GLANCE_SMOKE_BUILD:-0}"
case "$CONFIGURATION" in release|debug) ;; *) echo "Invalid GLANCE_CONFIGURATION" >&2; exit 1 ;; esac
case "$SMOKE_BUILD" in 0|1) ;; *) echo "Invalid GLANCE_SMOKE_BUILD" >&2; exit 1 ;; esac
if [[ "$SMOKE_BUILD" == 1 && "$CONFIGURATION" != debug ]]; then
    echo "Smoke bundles require GLANCE_CONFIGURATION=debug" >&2
    exit 1
fi
VERSION=$(cat VERSION)
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "VERSION must contain MAJOR.MINOR.PATCH" >&2
    exit 1
fi
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || GIT_ROOT=""
if [[ "$GIT_ROOT" == "$ROOT" ]] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    SOURCE_REVISION=$(git rev-parse --short=12 HEAD)
    DEFAULT_BUILD_NUMBER=$(git rev-list --count HEAD)
    if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then SOURCE_REVISION="$SOURCE_REVISION-dirty"; fi
else
    SOURCE_REVISION="unversioned"
    DEFAULT_BUILD_NUMBER=1
    echo "Building a source archive: Git revision information is unavailable." >&2
fi
BUILD_NUMBER="${GLANCE_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then echo "Invalid GLANCE_BUILD_NUMBER" >&2; exit 1; fi
BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
OUTPUT="$ROOT/build"
if [[ "$SMOKE_BUILD" == 1 ]]; then OUTPUT="$OUTPUT/smoke"; fi
for product in GlanceMonitor GlanceTime; do
    if [[ ! -s "$ROOT/Assets/$product.icns" ]]; then
        echo "Missing app icons. Run: swift -swift-version 6 Scripts/generate-icons.swift" >&2
        exit 1
    fi
done
swift build --configuration "$CONFIGURATION"
BIN_DIR=$(swift build --configuration "$CONFIGURATION" --show-bin-path)
mkdir -p "$OUTPUT"

package_app() {
    local product="$1"
    local display_name="$2"
    local identifier="$3"
    if [[ "$SMOKE_BUILD" == 1 ]]; then identifier="$identifier.smoke"; fi
    local destination="$OUTPUT/$display_name.app"
    local staging
    staging=$(mktemp -d "$OUTPUT/.package.XXXXXX")
    local app="$staging/$display_name.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
    cp "Assets/$product.icns" "$app/Contents/Resources/"
    cp "$BIN_DIR/$product" "$app/Contents/MacOS/$product"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>$product</string>
    <key>CFBundleIdentifier</key><string>$identifier</string>
    <key>CFBundleName</key><string>$display_name</string>
    <key>CFBundleDisplayName</key><string>$display_name</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>GlanceSourceRevision</key><string>$SOURCE_REVISION</string>
    <key>GlanceBuildDate</key><string>$BUILD_DATE</string>
    <key>CFBundleIconFile</key><string>$product.icns</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 Mohammad Juma</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
    codesign --force --sign - "$app"
    plutil -lint "$app/Contents/Info.plist"
    codesign --verify --strict "$app"
    swift -swift-version 6 Scripts/replace-app.swift "$app" "$destination"
    rmdir "$staging"
    printf 'Packaged %s\n' "$destination"
}

package_app "GlanceMonitor" "Glance Monitor" "com.local.glance.monitor"
package_app "GlanceTime" "Glance Time" "com.local.glance.time"
printf 'Local ad-hoc builds only; these bundles are not notarized for public distribution.\n'
