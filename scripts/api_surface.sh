#!/usr/bin/env bash
# The public API of HiPGR, and whether it still matches the recorded surface.
#
#   ./scripts/api_surface.sh            # check against docs/api-surface.txt
#   ./scripts/api_surface.sh --record   # rewrite docs/api-surface.txt
#
# A line per public declaration: functions with their parameter types, structs,
# and constants. Goose has no namespaces or privacy, so everything in the
# package is reachable; this file is what 0.5 calls the stable surface, and the
# policy in docs/COMPATIBILITY.md says what changing a line means.
#
# Removing or changing a recorded line is a breaking change and fails. Adding
# one is a feature: it is printed, and it belongs in CHANGELOG.md.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
surface="docs/api-surface.txt"

# Every declaration, normalised to one line. A declaration runs from its
# keyword until the brace that opens it, so wrapped signatures compare equal to
# the same signature on one line.
extract() {
    awk '
        FNR == 1 { collecting = 0 }
        {
            line = $0
            # Comments and blank lines never start a declaration.
            if (collecting == 0) {
                if (line ~ /^[[:space:]]*\/\// || line ~ /^[[:space:]]*$/) next
                if (line ~ /^(fn|root struct|struct|let) /) {
                    collecting = 1
                    acc = line
                } else next
            } else {
                acc = acc " " line
            }
            if (index(acc, "{") > 0 || (collecting == 1 && line !~ /,$/ && line !~ /=/ && acc ~ /}/)) {
                sub(/[[:space:]]*\{.*$/, "", acc)     # drop the body
                gsub(/[[:space:]]+/, " ", acc)
                sub(/[[:space:]]+$/, "", acc)
                print acc
                collecting = 0
            }
        }
    ' src/hipgr/*.goose | LC_ALL=C sort -u
}

if [ "${1:-}" = "--record" ]; then
    extract > "$surface"
    echo "recorded $(wc -l < "$surface") declarations in $surface"
    exit 0
fi

if [ ! -f "$surface" ]; then
    echo "error: $surface is missing; run ./scripts/api_surface.sh --record" >&2
    exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
extract > "$tmp"

removed="$(LC_ALL=C comm -23 "$surface" "$tmp")"
added="$(LC_ALL=C comm -13 "$surface" "$tmp")"

if [ -n "$removed" ]; then
    echo "FAIL api-surface: these declarations were removed or changed:"
    printf '%s\n' "$removed" | sed 's/^/    /'
    echo "  A change here breaks every application that used it. Either restore it,"
    echo "  or bump the minor version and record it in CHANGELOG.md with a migration"
    echo "  note, then run ./scripts/api_surface.sh --record."
    exit 1
fi

if [ -n "$added" ]; then
    echo "api-surface: $(printf '%s\n' "$added" | wc -l) new declaration(s), allowed in a minor:"
    printf '%s\n' "$added" | sed 's/^/    /'
    echo "  Record them with ./scripts/api_surface.sh --record and mention them in CHANGELOG.md."
    exit 1
fi

echo "ok   api-surface: $(wc -l < "$surface") declarations unchanged"
