#!/usr/bin/env bash
# Block-RAM graphics VRAM: random GRCG/EGC/GDC operations from two ports
# against a reference model, then readback on the display clock. The
# negative control expects OR instead of the EGC affine XOR merge.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/gvram_m10k_lanes_sim.vhd \
    rtl/graphics/gvram_m10k.vhd tests/gvram_m10k_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" gvram_m10k_tb
for seed in ${SEEDS:-1 2 3 4}; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" gvram_m10k_tb -gSEED="$seed" --assert-level=error
done
if ghdl -r --std=08 -fsynopsys --workdir="$out" gvram_m10k_tb -gBREAK_AFFINE=true --assert-level=error > "$out/neg.log" 2>&1; then
    echo 'FAIL: wrong affine merge model was accepted' >&2; exit 1
fi
grep -q 'mismatch' "$out/neg.log" || { cat "$out/neg.log"; exit 1; }
echo 'PASS: affine negative control rejected'
