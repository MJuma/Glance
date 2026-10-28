#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
swift build --configuration release
BIN_DIR=$(swift build --configuration release --show-bin-path)

package_app() {
    local product="$1"
    local display_name="$2"
    local identifier="$3"
    local app="$ROOT/build/$display_name.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
    cp "$BIN_DIR/$product" "$app/Contents/MacOS/$product.next"
    mv "$app/Contents/MacOS/$product.next" "$app/Contents/MacOS/$product"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>$product</string>
    <key>CFBundleIdentifier</key><string>$identifier</string>
    <key>CFBundleName</key><string>$display_name</string>
    <key>CFBundleDisplayName</key><string>$display_name</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
    codesign --force --sign - "$app"
    plutil -lint "$app/Contents/Info.plist"
    codesign --verify --strict "$app"
    printf 'Packaged %s\n' "$app"
}

package_app "GlanceMonitor" "Glance Monitor" "com.local.glance.monitor"
package_app "GlanceTime" "Glance Time" "com.local.glance.time"
printf 'Local ad-hoc builds only; these bundles are not notarized for public distribution.\n'
