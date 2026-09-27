#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# The isolated combinational test intentionally initializes DUT registers
# while its clock is held low. Full-core regressions separately exercise
# sequential operation and the same embedded equivalence assertions.
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-BLKANDNBLK -Wno-PINMISSING -Wno-UNOPTFLAT \
    -Irtl/vendor/z486 --Mdir "$out/obj" --top-module z486_prefetch_windows_tb \
    rtl/vendor/z486/z486_pkg.sv rtl/vendor/z486/z486_cache_map_pkg.sv rtl/vendor/z486/prefetch.sv \
    tests/z486_prefetch_windows_tb.sv > "$out/compile.log" 2>&1 || {
        tail -n 100 "$out/compile.log"; exit 1;
    }
"$out/obj/Vz486_prefetch_windows_tb"
