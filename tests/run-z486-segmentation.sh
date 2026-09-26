#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Irtl/vendor/z486 --Mdir "$out/obj" \
    --top-module z486_segmentation_tb rtl/vendor/z486/z486_pkg.sv \
    rtl/vendor/z486/segmentation_unit.sv tests/z486_segmentation_tb.sv \
    > "$out/compile.log" 2>&1 || {
        tail -n 100 "$out/compile.log"; exit 1;
    }
"$out/obj/Vz486_segmentation_tb"
