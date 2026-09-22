#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mkdir -p build/diagnostics
nasm -f bin -DPROBE_SHELL=1 -o build/diagnostics/grcg-compare-probe.com tests/hardware/grcg_compare_probe.asm
# Keep the diagnostic small enough for the 2,011-byte test-shell allocation.
# The fixture must separately verify which COM file CONFIG.SYS actually runs.
test "$(wc -c < build/diagnostics/grcg-compare-probe.com)" -le 2011
sha256sum build/diagnostics/grcg-compare-probe.com
python3 tests/test_grcg_compare_probe.py
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/grcg.vhd tests/grcg_compare_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grcg_compare_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" grcg_compare_tb --assert-level=error
for mutation in any_plane single_read disabled_plane tile_restart; do
    case "$mutation" in
        any_plane) sed 's/compare0 and compare1 and compare2 and compare3/compare0 or compare1 or compare2 or compare3/' Zet98/grcg.vhd > "$out/bad.vhd" ;;
        single_read) sed "s/memrd4<=.*prd when.*/memrd4<='0';/" Zet98/grcg.vhd > "$out/bad.vhd" ;;
        disabled_plane) sed "s/when PGEN(0)='1'/when true/" Zet98/grcg.vhd > "$out/bad.vhd" ;;
        tile_restart) sed 's/tilenum<=0; -- GRCG_MODE_RESTART/null; -- deliberately retain partial tile index/' Zet98/grcg.vhd > "$out/bad.vhd" ;;
    esac
    mkdir "$out/$mutation"
    ghdl -a --std=08 -fsynopsys --workdir="$out/$mutation" "$out/bad.vhd" tests/grcg_compare_tb.vhd
    ghdl -e --std=08 -fsynopsys --workdir="$out/$mutation" grcg_compare_tb
    if ghdl -r --std=08 -fsynopsys --workdir="$out/$mutation" grcg_compare_tb --assert-level=error > "$out/bad.log" 2>&1; then
        echo "FAIL: GRCG $mutation mutation accepted"; exit 1
    fi
    grep -Eq 'GRCG compare mismatch|GRCG compare did not request all four planes' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: GRCG $mutation mutation rejected"
done
