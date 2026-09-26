#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Model the exact constrained source-to-memory bundle, leaving request timing
# unchanged. The admission edge must have at least 5 ns of stable write data.
test "$(grep -c 'CPU_WRITE_BUNDLE_TRANSPORT' Zet98/sdramc.vhd)" = 1
test "$(grep -c 'CPU_WRITE_BUNDLE_ADMISSION' Zet98/sdramc.vhd)" = 1
for delay in 15 80; do
    sed -e "s/cpu_write_crossing <= cpu_write_source; -- CPU_WRITE_BUNDLE_TRANSPORT/cpu_write_crossing <= transport cpu_write_source after $delay ns;/" \
        -e "/CPU_WRITE_BUNDLE_ADMISSION/a\\                    assert cpu_write_crossing'stable(5 ns) report \"CPU write bundle arrived too late\" severity failure;" \
        Zet98/sdramc.vhd > "$out/sdram-$delay.vhd"
done
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd "$out/sdram-15.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for mhz in ${CPU_RATES:-20 40 50 60 90 100}; do
    for phase in 0 1300 4700 9100; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
            -gCPU_MHZ="$mhz" -gBUFFERED=true -gMEM_PHASE_PS="$phase" --assert-level=error
    done
done
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd "$out/sdram-80.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
    -gCPU_MHZ=60 -gBUFFERED=true --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: late write bundle was accepted' >&2; exit 1
fi
grep -Eq 'CPU write bundle arrived too late|SDRAM write data mismatch|SDRAM row/bank mismatch' "$out/negative.log"
echo 'PASS: late CPU write bundle rejected'

# Moving read capture one CPU cycle later must be rejected: the bus master
# consumes data with the existing ACK and must never see the previous read.
test "$(grep -c 'CPU_READ_COMPLETION_CAPTURE' Zet98/sdramc.vhd)" = 1
sed "s@if CPUdone_sync(1)/=CPUdone_seen then -- CPU_READ_COMPLETION_CAPTURE@if CPUACKb='1' then -- deliberately late read@" \
    Zet98/sdramc.vhd > "$out/sdram-late-read.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd "$out/sdram-late-read.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
    -gCPU_MHZ=60 -gBUFFERED=true --assert-level=error > "$out/late-read.log" 2>&1; then
    echo 'FAIL: late CPU read data was accepted' >&2; exit 1
fi
grep -q 'read data missing on ACK edge' "$out/late-read.log"
echo 'PASS: late CPU read capture rejected'
