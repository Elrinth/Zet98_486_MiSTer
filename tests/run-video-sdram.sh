#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd \
    Zet98/sdramc.vhd VIDEO/graphscr98.vhd tests/video_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" video_sdram_tb
for phase in 0 1 3333 5000 6667 9999; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" video_sdram_tb -gPHASE_PS="$phase" --assert-level=error
done
# Deliberately violate the bundled-data contract: the checker must reject it.
if ghdl -r --std=08 -fsynopsys --workdir="$out" video_sdram_tb -gDATA_DELAY_NS=200 --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: graphics capture accepted data arriving after its write strobe' >&2
    exit 1
fi
grep -Eq 'Graphics data changed|Missing, duplicate|Unknown graphics' "$out/negative.log"
echo 'PASS: late graphics-data negative control rejected'
