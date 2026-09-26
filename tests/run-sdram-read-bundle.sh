#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Last read word is captured at memory count 7 (single) / 10 (four words).
# Completion is asserted at count 8 / 11: >=10ns later, then sampled by CPU.
# Model 5ns data routing, requiring another 5ns stability at that capture.
# Only the return payload is delayed; completion/control keep normal timing.
for delay in 5 80; do
    sed -e "s/cpu_read_crossing <= cpu_read_words; -- CPU_READ_BUNDLE_TRANSPORT/cpu_read_crossing <= transport cpu_read_words after $delay ns;/" \
        -e "s/sub_read_crossing <= sub_read_words; -- SUB_READ_BUNDLE_TRANSPORT/sub_read_crossing <= transport sub_read_words after $delay ns;/" \
        -e "/CPU_READ_COMPLETION_CAPTURE/a\\                    assert cpu_read_crossing'stable(5 ns) report \"CPU return bundle arrived too late\" severity failure;" \
        -e "/SUB_READ_COMPLETION_CAPTURE/a\\                    assert sub_read_crossing'stable(5 ns) report \"SUB return bundle arrived too late\" severity failure;" \
        Zet98/sdramc.vhd > "$out/sdram-$delay.vhd"
done
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd "$out/sdram-5.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for sub in false true; do
    for mhz in ${CPU_RATES:-20 40 50 60 90 100}; do
        for phase in 0 417 833 1250 1667 2083 2500 2917 3333 3750 4167 4583 5000 5417 5833 6250 6667 7083 7500 7917 8333 8750 9167 9583; do
            ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
                -gUSE_SUB="$sub" -gCPU_MHZ="$mhz" -gBUFFERED=true -gMEM_PHASE_PS="$phase" --assert-level=error
        done
    done
done
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd "$out/sdram-80.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for sub in false true; do
    if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
        -gUSE_SUB="$sub" -gCPU_MHZ=100 -gBUFFERED=true --assert-level=error > "$out/bad-$sub.log" 2>&1; then
        echo "FAIL: late return bundle accepted SUB=$sub"; exit 1
    fi
    grep -Eq 'return bundle arrived too late|read data missing on ACK edge|four-plane data missing on ACK edge' "$out/bad-$sub.log"
    echo "PASS: late return bundle rejected SUB=$sub"
done
