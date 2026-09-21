#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Check the actual first pixel-clock capture, not only the later RAM write.
# Keeping the assertion in a temporary copy avoids synthesis-only changes.
sed '/WDAT0<=GRAMDAT0; WDAT1<=GRAMDAT1;/i\                    assert GRAMDAT0\x27stable(20 ns) and GRAMDAT1\x27stable(20 ns) and GRAMDAT2\x27stable(20 ns) and GRAMDAT3\x27stable(20 ns) report "Graphics data changed too close to WDAT capture" severity failure;' \
    VIDEO/GRAPHSCR98.vhd > "$out/graphics.vhd"
grep -q 'too close to WDAT capture' "$out/graphics.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd \
    Zet98/sdramc.vhd "$out/graphics.vhd" tests/video_sdram_tb.vhd
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
