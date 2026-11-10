#!/usr/bin/env bash
# Builds and runs every HiPGR test on a headless GPU device.
#
#   ./scripts/test.sh              # uses `goose` from PATH
#   GOOSE=/path/to/goose ./scripts/test.sh
#
# Each test is a Goose program that renders and checks the pixels it read back.
# A test prints PASS on success, SKIP when the machine has no GPU device (in
# which case nothing was validated), and aborts with a reason on failure.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
GOOSE="${GOOSE:-goose}"
export GOOSE_GFX_HEADLESS=1

pass=0
skip=0
failed=0
failed_names=""

report_fail() {
    failed=$((failed + 1))
    failed_names="$failed_names $1"
    echo "FAIL $1"
}

# A renderer test that imports the backend directly would not prove that
# applications can stay behind HiPGR's API.
if grep -rl --include='*.goose' -E '^import gfx;' examples tests bench > /dev/null 2>&1; then
    echo "FAIL api-isolation: these files import gfx directly:"
    grep -rl --include='*.goose' -E '^import gfx;' examples tests bench | sed 's/^/    /'
    failed=$((failed + 1))
    failed_names="$failed_names api-isolation"
fi

# Every example and benchmark must at least compile: they are the documented
# API in use.
for src in examples/*.goose bench/*.goose; do
    name="$(basename "$src" .goose)"
    if ! build_out="$(timeout 300 "$GOOSE" build "$src" 2>&1)"; then
        report_fail "$name (build)"
        echo "$build_out" | sed 's/^/    /' | head -30
    fi
    if printf '%s' "$build_out" | grep -qi 'warning:'; then
        report_fail "$name (warning)"
        printf '%s' "$build_out" | grep -i 'warning:' | sed 's/^/    /' | head -10
    fi
done

for src in tests/test_*.goose; do
    name="$(basename "$src" .goose)"
    exe="${src%.goose}"
    [ -x "$GOOSE" ] || command -v "$GOOSE" > /dev/null 2>&1 || {
        echo "error: goose not found (set GOOSE=/path/to/goose)" >&2
        exit 2
    }
    if ! build_out="$(timeout 300 "$GOOSE" build "$src" 2>&1)"; then
        report_fail "$name (build)"
        echo "$build_out" | sed 's/^/    /' | head -30
        continue
    fi
    if printf '%s' "$build_out" | grep -qi 'warning:'; then
        report_fail "$name (warning)"
        printf '%s' "$build_out" | grep -i 'warning:' | sed 's/^/    /' | head -10
        continue
    fi
    run_out="$(timeout 300 "$exe" 2>&1)"
    status=$?
    if [ $status -ne 0 ]; then
        report_fail "$name (exit $status)"
        echo "$run_out" | grep -v '^Installed Vulkan' | sed 's/^/    /' | head -30
        continue
    fi
    if printf '%s' "$run_out" | grep -q '^SKIP '; then
        skip=$((skip + 1))
        echo "SKIP $name"
    else
        pass=$((pass + 1))
        echo "ok   $name"
    fi
done

echo
echo "$pass passed, $skip skipped, $failed failed"
[ "$failed" -eq 0 ] || {
    echo "failed:$failed_names"
    exit 1
}
