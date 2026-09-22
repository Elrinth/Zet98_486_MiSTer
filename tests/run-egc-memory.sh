#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
make_variant() {
    sed -e "s/cpu_write_crossing <= cpu_write_source; -- CPU_WRITE_BUNDLE_TRANSPORT/cpu_write_crossing <= transport cpu_write_source after $1 ns;/" \
        -e "/CPU_WRITE_BUNDLE_ADMISSION/a\\                    assert cpu_write_crossing'stable(5 ns) report \"CPU write bundle arrived too late\" severity failure;" \
        Zet98/sdramc.vhd > "$2"
}
make_variant 15 "$out/sdram.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram.vhd" tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
# All 256 operations x 16 plane masks x four byte masks, plus ordinary/RMW
# compatibility while the optional feature is enabled but not selected.
ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
    -gCPU_MHZ=60 -gBUFFERED=true -gAFFINE_TEST=true -gMEM_PHASE_PS=4700 -gHOLD_COMPLETION_CYCLES=3 --assert-level=error
for mhz in 20 50 60 90 100; do
    for phase in 0 4700; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
            -gCPU_MHZ="$mhz" -gBUFFERED=true -gAFFINE_TEST=true -gAFFINE_CASES=1024 \
            -gMEM_PHASE_PS="$phase" --assert-level=error
    done
done
for mutation in or live_mode live_mask late; do
    case "$mutation" in
        or) sed 's/cpu_write_memory(i\*16+15 downto i\*16) xor/cpu_write_memory(i*16+15 downto i*16) or/' Zet98/sdramc.vhd > "$out/bad.vhd" ;;
        live_mode) sed "s/cpu_write_memory(ADRWIDTH+152)='1'/CPUAFFINE='1'/" Zet98/sdramc.vhd > "$out/bad.vhd" ;;
        live_mask) sed 's/cpu_write_memory(ADRWIDTH+103+i\*16 downto ADRWIDTH+88+i\*16)/CPUXORMASK(i*16+15 downto i*16)/' Zet98/sdramc.vhd > "$out/bad.vhd" ;;
        late) make_variant 80 "$out/bad.vhd" ;;
    esac
    mkdir "$out/$mutation"
    ghdl -a --std=08 -fsynopsys --workdir="$out/$mutation" "$out/bad.vhd" tests/sdram_request_tb.vhd
    ghdl -e --std=08 -fsynopsys --workdir="$out/$mutation" sdram_request_tb
    if ghdl -r --std=08 -fsynopsys --workdir="$out/$mutation" sdram_request_tb \
        -gCPU_MHZ=60 -gBUFFERED=true -gAFFINE_TEST=true -gAFFINE_CASES=1024 --assert-level=error > "$out/bad.log" 2>&1; then
        echo "FAIL: affine memory $mutation mutation accepted"; exit 1
    fi
    grep -Eq 'SDRAM write data mismatch|CPU write bundle arrived too late|SDRAM row/bank mismatch' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: affine memory $mutation mutation rejected"
done
