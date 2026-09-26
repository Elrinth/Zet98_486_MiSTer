#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZ486_ALTERA_ALU \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_gpr_forward_tb "${sources[@]}" tests/z486_gpr_forward_tb.sv \
    > "$out/compile.log" 2>&1 || { tail -n 70 "$out/compile.log"; exit 1; }
"$out/obj/Vz486_gpr_forward_tb"
