#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$ROOT"
VERSION=$(cat VERSION)
TAG="${GLANCE_RELEASE_TAG:-v$VERSION}"
if [[ "$TAG" != "v$VERSION" ]]; then echo "Release tag must match VERSION (v$VERSION)." >&2; exit 1; fi
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || GIT_ROOT=""
if [[ "$GIT_ROOT" != "$ROOT" ]] || ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Release preparation requires a Git checkout." >&2
    exit 1
fi
suffix=""
DEVELOPER_BUILD="${GLANCE_ALLOW_DIRTY_RELEASE:-0}"
case "$DEVELOPER_BUILD" in 0|1) ;; *) echo "Invalid GLANCE_ALLOW_DIRTY_RELEASE" >&2; exit 1 ;; esac
if [[ -n "$(git status --porcelain --untracked-files=normal)" && "$DEVELOPER_BUILD" != 1 ]]; then
    echo "Refusing to package a release from dirty sources." >&2
    exit 1
fi
if [[ "$DEVELOPER_BUILD" == 1 ]]; then
    suffix="-dev"
    echo "Preparing developer artifacts, not a publishable release." >&2
else
    if ! TAG_COMMIT=$(git rev-parse --verify "refs/tags/$TAG^{commit}" 2>/dev/null); then
        echo "Release tag does not exist: $TAG" >&2
        exit 1
    fi
    if [[ "$TAG_COMMIT" != "$(git rev-parse HEAD)" ]]; then
        echo "Release tag does not point to the current checkout." >&2
        exit 1
    fi
fi
destination="$ROOT/dist/$TAG$suffix"
if [[ -e "$destination" ]]; then
    echo "Artifact destination already exists: $destination. It was not overwritten." >&2
    exit 1
fi
case "$(uname -m)" in arm64|x86_64) arch=$(uname -m) ;; *) echo "Unsupported build architecture." >&2; exit 1 ;; esac
GLANCE_CONFIGURATION=release GLANCE_SMOKE_BUILD=0 bash Scripts/build-apps.sh
if [[ "$DEVELOPER_BUILD" == 0 ]] && {
    [[ -n "$(git status --porcelain --untracked-files=normal)" ]] ||
    [[ "$(git rev-parse HEAD)" != "$TAG_COMMIT" ]] ||
    [[ "$(git rev-parse --verify "refs/tags/$TAG^{commit}" 2>/dev/null)" != "$TAG_COMMIT" ]]
}; then
    echo "Source checkout or release tag changed while building the release." >&2
    exit 1
fi
mkdir -p "$ROOT/dist"
stage=$(mktemp -d "$ROOT/dist/.release.XXXXXX")

for product in GlanceMonitor GlanceTime; do
    if [[ "$product" == GlanceMonitor ]]; then name="Glance Monitor"; else name="Glance Time"; fi
    app="$ROOT/build/$name.app"
    app_version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
    if [[ "$app_version" != "$VERSION" ]]; then echo "Bundle/version mismatch." >&2; exit 1; fi
    if [[ "$DEVELOPER_BUILD" == 0 ]]; then
        revision=$(plutil -extract GlanceSourceRevision raw "$app/Contents/Info.plist")
        if [[ "$revision" != "$(git rev-parse --short=12 HEAD)" ]]; then
            echo "Bundle/source-revision mismatch." >&2
            exit 1
        fi
    fi
    codesign --verify --strict "$app"
    archive="$product-$VERSION-macos-$arch-adhoc$suffix.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$archive"
    verification=$(mktemp -d "$stage/.verify.XXXXXX")
    ditto -x -k "$stage/$archive" "$verification"
    codesign --verify --strict "$verification/$name.app"
    cmp "$app/Contents/MacOS/$product" "$verification/$name.app/Contents/MacOS/$product"
    cmp LICENSE "$verification/$name.app/Contents/Resources/LICENSE"
    cmp THIRD_PARTY_NOTICES.md "$verification/$name.app/Contents/Resources/THIRD_PARTY_NOTICES.md"
    swift -swift-version 6 Scripts/remove-release-verification.swift "$verification"
done
(
    cd "$stage"
    shasum -a 256 ./*.zip > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
swift -swift-version 6 - "$stage" "$destination" <<'SWIFT'
import Foundation
try FileManager.default.moveItem(
    at: URL(fileURLWithPath: CommandLine.arguments[1]),
    to: URL(fileURLWithPath: CommandLine.arguments[2])
)
SWIFT
printf 'Verified local artifacts: %s\n' "$destination"
printf 'Ad-hoc signatures and checksums do not provide notarization or an Apple-trusted publisher identity.\n'
