#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cc -std=c99 -O2 -fno-strict-aliasing -Wall -Wextra -o "$out/reference" tests/egc_write_reference.c
"$out/reference" "$out/vectors.txt"
iverilog -g2012 -Wall -s egc_write_tb -o "$out/write" \
    rtl/graphics/pc98_egc_rop.sv rtl/graphics/pc98_egc_write.sv tests/egc_write_tb.sv
vvp "$out/write" +vectors="$out/vectors.txt"
for mutation in stale_pattern raw_pattern cpu_source clip; do
    case "$mutation" in
        stale_pattern) sed "s/color_mode == 0 \&\& pattern_load == 2/1'b0/" rtl/graphics/pc98_egc_write.sv > "$out/bad.sv" ;;
        raw_pattern) sed 's/? shifted_source : pattern_words/? pattern_words : pattern_words/' rtl/graphics/pc98_egc_write.sv > "$out/bad.sv" ;;
        cpu_source) sed 's/{4{cpu_writedata}}/shifted_source/' rtl/graphics/pc98_egc_write.sv > "$out/bad.sv" ;;
        clip) sed 's/pixel_mask \& clip_mask/pixel_mask/' rtl/graphics/pc98_egc_write.sv > "$out/bad.sv" ;;
    esac
    iverilog -g2012 -s egc_write_tb -o "$out/bad" rtl/graphics/pc98_egc_rop.sv "$out/bad.sv" tests/egc_write_tb.sv
    if vvp "$out/bad" +vectors="$out/vectors.txt" > "$out/bad.log" 2>&1; then
        echo "FAIL: EGC write $mutation mutation accepted"; exit 1
    fi
    grep -q 'EGC write.*mismatch' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: EGC write $mutation mutation rejected"
done
