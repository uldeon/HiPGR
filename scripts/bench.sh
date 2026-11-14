#!/usr/bin/env bash
# Builds and runs the HiPGR frame benchmark on a headless device.
#
#   ./scripts/bench.sh [cubes] [frames] [10k side] [10k frames]
#
# The first pair is bench_scene (N cubes, linear vs modern), the second is
# bench_10k (a side x side grid, with and without culling and batching).
#
# These are numbers from whatever GPU the machine has. In the development
# container that is Mesa's llvmpipe software Vulkan device, which is useful for
# catching regressions and useless as a statement about real hardware; see
# RECONNAISSANCE.md.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
GOOSE="${GOOSE:-goose}"
export GOOSE_GFX_HEADLESS=1

"$GOOSE" build bench/bench_scene.goose || exit 1
./bench/bench_scene "${1:-256}" "${2:-60}"

"$GOOSE" build bench/bench_10k.goose || exit 1
./bench/bench_10k "${3:-100}" "${4:-20}"
