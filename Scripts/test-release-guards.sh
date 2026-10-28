#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/glance-release-guards.XXXXXX")
fixture=$(cd "$fixture" && pwd -P)
cleanup() {
    swift - "$fixture" <<'SWIFT'
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard url.lastPathComponent.hasPrefix("glance-release-guards.") else {
    fatalError("Refusing to remove an unexpected fixture path")
}
try FileManager.default.removeItem(at: url)
SWIFT
}
trap cleanup EXIT

git_fixture() {
    git -C "$fixture" -c user.name='Release Guard Tests' \
        -c user.email='release-tests@example.invalid' -c commit.gpgsign=false \
        -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

mkdir "$fixture/Scripts"
cp "$ROOT/Scripts/package-release.sh" "$fixture/Scripts/"
printf '1.0.0\n' > "$fixture/VERSION"
cat > "$fixture/Scripts/build-apps.sh" <<'BUILD'
#!/bin/bash
set -euo pipefail
case "$GLANCE_TEST_RELEASE_MODE" in
    probe) echo BUILD_REACHED; exit 73 ;;
    delete-tag) git update-ref -d refs/tags/v1.0.0 ;;
    move-tag) git update-ref refs/tags/v1.0.0 "$(git rev-parse HEAD^)" ;;
    move-head) git update-ref HEAD "$(git rev-parse HEAD^)" ;;
    *) echo "Unexpected fixture mode" >&2; exit 1 ;;
esac
BUILD
git_fixture init --quiet --initial-branch main
git_fixture add --force VERSION Scripts
git_fixture commit --quiet -m 'Initial fixture'
git_fixture commit --quiet --allow-empty -m 'Second fixture commit'

expect_result() {
    local name="$1" mode="$2" expected_status="$3" message="$4" output status=0
    output=$(GLANCE_ALLOW_DIRTY_RELEASE=0 GLANCE_RELEASE_TAG=v1.0.0 \
        GLANCE_TEST_RELEASE_MODE="$mode" bash "$fixture/Scripts/package-release.sh" 2>&1) || status=$?
    if [[ "$status" != "$expected_status" ]] || ! grep -Fq "$message" <<< "$output"; then
        printf 'FAILED: %s (status %s)\n%s\n' "$name" "$status" "$output" >&2
        exit 1
    fi
    printf 'Passed: %s\n' "$name"
}

expect_result 'missing tag rejected' probe 1 'Release tag does not exist'
git_fixture branch v1.0.0
expect_result 'same-named branch is not a tag' probe 1 'Release tag does not exist'
git_fixture tag v1.0.0
expect_result 'lightweight tag reaches build' probe 73 BUILD_REACHED
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag --annotate v1.0.0 -m 'Annotated fixture tag'
expect_result 'annotated tag reaches build' probe 73 BUILD_REACHED
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag v1.0.0 HEAD^
expect_result 'tag at another commit rejected' probe 1 'Release tag does not point'
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag v1.0.0
expect_result 'tag deleted during build rejected' delete-tag 1 'Source checkout or release tag changed'
git_fixture tag v1.0.0
expect_result 'tag moved during build rejected' move-tag 1 'Source checkout or release tag changed'
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag v1.0.0
expect_result 'HEAD moved during build rejected' move-head 1 'Source checkout or release tag changed'
printf 'All release-tag guard checks passed.\n'
