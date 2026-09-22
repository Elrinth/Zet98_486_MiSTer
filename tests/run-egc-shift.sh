#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/egc_shift_vectors.py generate "$out/input.txt"
cc -std=c99 -O2 -Wall -Wextra -o "$out/reference" tests/egc_shift_reference.c
"$out/reference" "$out/input.txt" "$out/vectors.txt"
python3 tests/egc_shift_vectors.py verify "$out/vectors.txt"
for registers in 0 1; do
    iverilog -g2012 -Wall -s egc_shift_tb -Pegc_shift_tb.USE_REGISTERS=$registers -o "$out/shift" \
        rtl/graphics/pc98_egc_registers.sv rtl/graphics/pc98_egc_shift.sv tests/egc_shift_tb.sv
    vvp "$out/shift" +vectors="$out/vectors.txt"
done
# Reject losing carry-over pixels, wrong native byte order, no clipping and
# failure to restart alignment at the next row. The same full corpus is used.
for mutation in carry order clipping reload; do
    case "$mutation" in
        carry) sed "s/{16'b0, pending\[p\]}/32'b0/" rtl/graphics/pc98_egc_shift.sv > "$out/bad.sv" ;;
        order) sed 's/? 7-b : 23-b/? 15-b : 15-b/g' rtl/graphics/pc98_egc_shift.sv > "$out/bad.sv" ;;
        clipping) sed "s/clip_mask <= next_mask;/clip_mask <= 16'hffff;/" rtl/graphics/pc98_egc_shift.sv > "$out/bad.sv" ;;
        reload) sed "s/if (row_done) begin/if (1'b0) begin/" rtl/graphics/pc98_egc_shift.sv > "$out/bad.sv" ;;
    esac
    iverilog -g2012 -s egc_shift_tb -o "$out/bad" rtl/graphics/pc98_egc_registers.sv "$out/bad.sv" tests/egc_shift_tb.sv
    if vvp "$out/bad" +vectors="$out/vectors.txt" > "$out/bad.log" 2>&1; then
        echo "FAIL: EGC shift $mutation mutation accepted"; exit 1
    fi
    grep -q 'EGC shift mismatch' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: EGC shift $mutation mutation rejected"
done
