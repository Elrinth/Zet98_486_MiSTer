#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/VTIMING.vhd tests/video_counter_timing_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" video_counter_timing_tb
for phase in 0 1 6 13 26 39; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" video_counter_timing_tb -gRELEASE_PHASE_NS="$phase" --assert-level=error
done
