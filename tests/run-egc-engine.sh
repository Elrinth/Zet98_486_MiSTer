#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl --synth --std=08 -fsynopsys --out=verilog -gADRWIDTH=22 \
    -gCPU_WRITE_BUNDLE=true -gSUB_WRITE_BUNDLE=true -gFLOPPY_REQUEST_BUNDLE=true \
    -gCPU_AFFINE_RMW=true tests/lcell_model.vhd Zet98/sdramc.vhd -e sdramc > "$out/memory.v" 2> "$out/synthesis.log" || {
    cat "$out/synthesis.log"; exit 1;
}
grep -q '^module SDRAMC$' "$out/memory.v" || { head -n 2 "$out/memory.v"; exit 1; }
sources=(rtl/graphics/pc98_egc_registers.sv rtl/graphics/pc98_egc_shift.sv
         rtl/graphics/pc98_egc_rop.sv rtl/graphics/pc98_egc_write.sv tests/egc_sdram_port.sv)
for mhz in 20 60 100; do
    for phase in 0 4700; do
        full=0
        if [[ "$mhz" = 60 && "$phase" = 0 ]]; then full=1; fi
        iverilog -g2012 -s egc_word_engine_tb -Pegc_word_engine_tb.CPU_MHZ="$mhz" \
            -Pegc_word_engine_tb.MEM_PHASE_PS="$phase" -Pegc_word_engine_tb.FULL="$full" \
            -o "$out/engine" "${sources[@]}" rtl/graphics/pc98_egc_word_engine.sv "$out/memory.v" tests/egc_word_engine_tb.sv
        if ! vvp "$out/engine"; then
            # Keep reproducible evidence when crossing the VHDL/SV boundary.
            mkdir -p build/egc-engine-failure
            cp "$out/memory.v" "$out/synthesis.log" build/egc-engine-failure/
            (cd build/egc-engine-failure; vvp "$out/engine" +trace > trace.log 2>&1) || true
            exit 1
        fi
    done
done
for mutation in retained_pattern replay read_shift early_ack reset_early; do
    case "$mutation" in
        retained_pattern) sed 's/if (load_on_write) pattern_latch<=pattern_merge;/if (load_on_write) pattern_latch<=memory_base;/' rtl/graphics/pc98_egc_word_engine.sv > "$out/bad.sv" ;;
        replay) sed 's/RELEASE: if (!request || reset_pending) state<=IDLE;/RELEASE: state<=IDLE;/' rtl/graphics/pc98_egc_word_engine.sv > "$out/bad.sv" ;;
        read_shift) sed 's/state == READ_MEMORY \&\& memory_acknowledge \&\& !transfer_operation\[10\]/state == READ_MEMORY \&\& !transfer_operation[10]/' rtl/graphics/pc98_egc_word_engine.sv > "$out/bad.sv" ;;
        early_ack) sed 's/WRITE_MEMORY: if (memory_acknowledge)/WRITE_MEMORY: if (1\x27b1)/' rtl/graphics/pc98_egc_word_engine.sv > "$out/bad.sv" ;;
        reset_early) sed 's/reset || (reset_pending \&\& state == IDLE)/reset || reset_pending/' rtl/graphics/pc98_egc_word_engine.sv > "$out/bad.sv" ;;
    esac
    iverilog -g2012 -s egc_word_engine_tb -Pegc_word_engine_tb.FULL=0 -o "$out/bad" \
        "${sources[@]}" "$out/bad.sv" "$out/memory.v" tests/egc_word_engine_tb.sv
    if vvp "$out/bad" > "$out/bad.log" 2>&1; then
        echo "FAIL: EGC engine $mutation mutation accepted"; exit 1
    fi
    grep -Eq 'EGC.*(mismatch|replayed|complete)' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: EGC engine $mutation mutation rejected"
done
