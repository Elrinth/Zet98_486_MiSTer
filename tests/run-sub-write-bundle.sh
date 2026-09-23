#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Model the exact constrained source-to-memory bundle, leaving request timing
# unchanged. The admission edge must have at least 5 ns of stable write data.
test "$(grep -c 'SUB_WRITE_BUNDLE_TRANSPORT' Zet98/sdramc.vhd)" = 1
test "$(grep -c 'SUB_WRITE_BUNDLE_ADMISSION' Zet98/sdramc.vhd)" = 1
for delay in 15 80; do
    sed -e "s/sub_write_crossing <= sub_write_source; -- SUB_WRITE_BUNDLE_TRANSPORT/sub_write_crossing <= transport sub_write_source after $delay ns;/" \
        -e "/SUB_WRITE_BUNDLE_ADMISSION/a\\                    assert sub_write_crossing'stable(5 ns) report \"SUB write bundle arrived too late\" severity failure;" \
        Zet98/sdramc.vhd > "$out/sdram-$delay.vhd"
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-15.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for mhz in ${CPU_RATES:-20 40 50 60 90 100}; do
    for phase in 0 1300 4700 9100; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gUSE_SUB=true \
            -gCPU_MHZ="$mhz" -gBUFFERED=true -gMEM_PHASE_PS="$phase" --assert-level=error
    done
done
# Preserve the original drawing-port behavior when the feature is disabled.
for mhz in 20 40 50 60; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gUSE_SUB=true \
        -gCPU_MHZ="$mhz" -gBUFFERED=false --assert-level=error
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-80.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gUSE_SUB=true \
    -gCPU_MHZ=60 -gBUFFERED=true --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: late write bundle was accepted' >&2; exit 1
fi
grep -Eq 'SUB write bundle arrived too late|SDRAM write data mismatch|SDRAM (row|column)/bank mismatch' "$out/negative.log"
echo 'PASS: late SUB write bundle rejected'

# Moving read capture one SUB cycle later must be rejected: the bus master
# consumes data with the existing ACK and must never see the previous read.
test "$(grep -c 'SUB_READ_COMPLETION_CAPTURE' Zet98/sdramc.vhd)" = 1
sed "s@if SUBdone_sync(1)/=SUBdone_seen then -- SUB_READ_COMPLETION_CAPTURE@if SUBACKb='1' then -- deliberately late read@" \
    Zet98/sdramc.vhd > "$out/sdram-late-read.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-late-read.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gUSE_SUB=true \
    -gCPU_MHZ=60 -gBUFFERED=true --assert-level=error > "$out/late-read.log" 2>&1; then
    echo 'FAIL: late SUB read data was accepted' >&2; exit 1
fi
grep -q 'read data missing on ACK edge' "$out/late-read.log"
echo 'PASS: late SUB read capture rejected'
