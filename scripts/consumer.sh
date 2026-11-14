#!/usr/bin/env bash
# Builds and runs integration/consumer.goose from a *clean copy* of this tree.
#
#   ./scripts/consumer.sh
#
# The point is not that the consumer compiles here — it is that a copy of the
# repository with no build artifacts, no local edits outside the tracked files,
# and no HiPGR-specific setup is enough for an application to build against the
# package and render. That is as close as this repository can come to 0.5's
# "an external project builds against a tagged version": a second remote is not
# available here, so the consumer is built from the tree at this commit.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
GOOSE="${GOOSE:-goose}"

if ! command -v "$GOOSE" > /dev/null 2>&1 && [ ! -x "$GOOSE" ]; then
    echo "error: goose not found (set GOOSE=/path/to/goose)" >&2
    exit 2
fi

if grep -q '^import gfx;' integration/consumer.goose; then
    echo "FAIL consumer: the consumer imports the backend directly"
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Everything git would carry: tracked files plus untracked ones that are not
# ignored. No binaries, no screenshots, no .git.
if ! git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null | tar -xf - -C "$tmp"; then
    echo "error: could not copy the tree" >&2
    exit 2
fi

if [ ! -f "$tmp/integration/consumer.goose" ]; then
    echo "error: integration/consumer.goose is not in the copied tree" >&2
    exit 2
fi

echo "building the consumer in a clean copy of $(git rev-parse --short HEAD 2>/dev/null || echo 'this tree')"
if ! out="$(cd "$tmp" && "$GOOSE" build integration/consumer.goose 2>&1)"; then
    echo "FAIL consumer (build)"
    printf '%s\n' "$out" | sed 's/^/    /' | head -30
    exit 1
fi
if printf '%s' "$out" | grep -qi 'warning:'; then
    echo "FAIL consumer (warning)"
    printf '%s' "$out" | grep -i 'warning:' | sed 's/^/    /' | head -10
    exit 1
fi

if ! run_out="$(cd "$tmp" && GOOSE_GFX_HEADLESS=1 ./integration/consumer 2>&1)"; then
    echo "FAIL consumer (run)"
    printf '%s\n' "$run_out" | grep -v '^Installed Vulkan' | sed 's/^/    /' | head -20
    exit 1
fi
if printf '%s' "$run_out" | grep -q '^SKIP '; then
    echo "SKIP consumer (no GPU device)"
    exit 0
fi
printf '%s\n' "$run_out" | grep -v '^Installed Vulkan'
printf '%s' "$run_out" | grep -q '^PASS consumer' || {
    echo "FAIL consumer: no PASS line"
    exit 1
}
echo "ok   consumer: an out-of-package application built and rendered from a clean copy"
