#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for delay in 5 80; do
    sed -e "s/fde_read_crossing <= fde_read_data; -- FDE_READ_BUNDLE_TRANSPORT/fde_read_crossing <= transport fde_read_data after $delay ns;/" \
        -e "s/fec_read_crossing <= fec_read_data; -- FEC_READ_BUNDLE_TRANSPORT/fec_read_crossing <= transport fec_read_data after $delay ns;/" \
        -e "/FDE_READ_COMPLETION_CAPTURE/a\\                    assert fde_read_crossing'stable(5 ns) report \"floppy return bundle arrived too late\" severity failure;" \
        -e "/FEC_READ_COMPLETION_CAPTURE/a\\                    assert fec_read_crossing'stable(5 ns) report \"floppy return bundle arrived too late\" severity failure;" \
        Zet98/sdramc.vhd > "$out/sdram-$delay.vhd"
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-5.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for port in false true; do
    for mhz in 20 40 50 60 90 100; do
        for phase in 0 417 833 1250 1667 2083 2500 2917 3333 3750 4167 4583 5000 5417 5833 6250 6667 7083 7500 7917 8333 8750 9167 9583; do
            ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb \
                -gUSE_FEC="$port" -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" -gCONTINUOUS=true --assert-level=error
        done
    done
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-80.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for port in false true; do
    if ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb -gUSE_FEC="$port" \
        -gCPU_MHZ=100 -gCONTINUOUS=true --assert-level=error > "$out/bad.log" 2>&1; then
        echo 'FAIL: late floppy return bundle accepted'; exit 1
    fi
    grep -Eq 'floppy return bundle arrived too late|floppy read data missing on WAIT completion' "$out/bad.log"
    echo "PASS: late floppy return rejected FEC=$port"
done
