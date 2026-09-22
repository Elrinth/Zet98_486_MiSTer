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
    rtl/reset_release.vhd rtl/display_page_address.vhd \
    Zet98/sdramc.vhd "$out/graphics.vhd" tests/video_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" video_sdram_tb
for mhz in ${CPU_RATES:-20 40 50 60 90 100}; do
    for phase in ${VIDEO_PHASES:-0 1 3333 5000 6667 9999}; do
      for delay in ${VIDEO_DATA_DELAYS:-0 20 40}; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" video_sdram_tb -gCPU_MHZ="$mhz" -gPHASE_PS="$phase" -gDATA_DELAY_NS="$delay" --assert-level=error
      done
    done
done
# Deliberately violate the bundled-data contract: the checker must reject it.
if ghdl -r --std=08 -fsynopsys --workdir="$out" video_sdram_tb -gDATA_DELAY_NS=200 --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: graphics capture accepted data arriving after its write strobe' >&2
    exit 1
fi
grep -Eq 'Graphics data changed|Missing, duplicate|Unknown graphics|Graphics plane from wrong display page' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS: late graphics-data negative control rejected'

# Corrupt data only AFTER the enabled capture. Earlier setup/data-order
# assertions cannot detect this fault; the post-capture monitor must do so.
if ghdl -r --std=08 -fsynopsys --workdir="$out" video_sdram_tb -gHOLD_GLITCH=true --assert-level=error > "$out/hold-negative.log" 2>&1; then
    echo 'FAIL: graphics capture accepted a post-capture hold violation' >&2; exit 1
fi
grep -q 'Graphics data changed after enabled WDAT capture' "$out/hold-negative.log" || { cat "$out/hold-negative.log"; exit 1; }
echo 'PASS: post-capture graphics-data glitch rejected'

# A live CPU page bypass must be caught by the memory-row check.
sed "s/when page_sync(1)='0'/when cpu_page='0'/" rtl/display_page_address.vhd > "$out/bad-page.vhd"
# Start the bypass control at page zero so it reaches a live page change,
# rather than failing only the independent reset-to-front assertion.
sed "s/signal cpu_page : std_logic := '1';/signal cpu_page : std_logic := '0';/" tests/video_sdram_tb.vhd > "$out/page-bypass-tb.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/bad-page.vhd" "$out/page-bypass-tb.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out" video_sdram_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" video_sdram_tb --assert-level=error > "$out/bad-page.log" 2>&1; then
    echo 'FAIL: unsynchronized display-page bypass passed' >&2; exit 1
fi
grep -q 'unsynchronized graphics display page' "$out/bad-page.log" || { cat "$out/bad-page.log"; exit 1; }
echo 'PASS: live display-page negative control rejected'
