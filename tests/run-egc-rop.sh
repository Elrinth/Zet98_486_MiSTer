#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s egc_rop_tb -o "$out/rop" rtl/graphics/pc98_egc_rop.sv tests/egc_rop_tb.sv
vvp "$out/rop"
# An OR-only RMW merge cannot represent destination inversion. Also reject
# swapping source/pattern and accidentally writing disabled bits.
for mutation in or swapped unmasked; do
    case "$mutation" in
        or) sed 's/base_words \^ (destination_words/base_words | (destination_words/' rtl/graphics/pc98_egc_rop.sv > "$out/bad.sv" ;;
        swapped) sed -e 's/source_words\[bit_index\]/TEMP_BIT/g' -e 's/pattern_words\[bit_index\]/source_words[bit_index]/g' -e 's/TEMP_BIT/pattern_words[bit_index]/g' rtl/graphics/pc98_egc_rop.sv > "$out/bad.sv" ;;
        unmasked) sed 's/enabled \& when_zero/when_zero/' rtl/graphics/pc98_egc_rop.sv > "$out/bad.sv" ;;
    esac
    iverilog -g2012 -s egc_rop_tb -o "$out/bad" "$out/bad.sv" tests/egc_rop_tb.sv
    if vvp "$out/bad" > "$out/bad.log" 2>&1; then
        echo "FAIL: EGC $mutation mutation accepted"; exit 1
    fi
    grep -q 'EGC ROP mismatch' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: EGC $mutation mutation rejected"
done
