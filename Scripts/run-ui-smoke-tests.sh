#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
GLANCE_CONFIGURATION=debug GLANCE_SMOKE_BUILD=1 bash Scripts/build-apps.sh

child=""
log=""
executable=""
cleanup() {
    if [[ -n "$child" ]]; then
        local parent command
        parent=$(ps -p "$child" -o ppid= | tr -d ' ') || parent=""
        command=$(ps -p "$child" -o command=) || command=""
        if [[ "$parent" == "$$" && "$command" == "$executable" ]]; then
            kill "$child" 2>/dev/null || true
            wait "$child" 2>/dev/null || true
        fi
    fi
    if [[ -n "$log" ]]; then rm -f "$log"; fi
}
trap cleanup EXIT

for product in GlanceMonitor GlanceTime; do
    if [[ "$product" == GlanceMonitor ]]; then name="Glance Monitor"; else name="Glance Time"; fi
    app="$ROOT/build/smoke/$name.app"
    identifier=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
    if [[ "$identifier" != "com.local.glance."*".smoke" ]]; then
        echo "Refusing to run a non-isolated smoke bundle." >&2
        exit 1
    fi
    executable="$app/Contents/MacOS/$product"
    log=$(mktemp "${TMPDIR:-/tmp}/glance-ui-smoke.XXXXXX")
    GLANCE_UI_SMOKE=1 "$executable" > "$log" 2>&1 &
    child=$!
    deadline=$((SECONDS + 60))
    while jobs -pr | grep -Fxq "$child"; do
        if (( SECONDS >= deadline )); then
            cat "$log"
            echo "$product lifecycle smoke test timed out." >&2
            exit 1
        fi
        sleep 0.1
    done
    status=0
    wait "$child" || status=$?
    child=""
    cat "$log"
    if (( status != 0 )) || ! grep -Fxq 'GLANCE_UI_SMOKE_SUCCESS' "$log"; then
        echo "$product lifecycle smoke test failed (status $status)." >&2
        exit 1
    fi
    rm -f "$log"
    log=""
done
printf 'Both isolated Debug lifecycle smoke tests passed.\n'
