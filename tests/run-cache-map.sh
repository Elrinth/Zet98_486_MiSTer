#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
source=Zet98/Zet98MiSTer.vhd
test "$(grep -c -- '-- BEGIN PC98 CACHE INVALIDATION' "$source")" = 1
test "$(grep -c -- '-- END PC98 CACHE INVALIDATION' "$source")" = 1
sed '$d' tests/cache_map_tb.vhd > "$out/cache_map_tb.vhd"
sed -n '/-- BEGIN PC98 CACHE INVALIDATION/,/-- END PC98 CACHE INVALIDATION/p' "$source" >> "$out/cache_map_tb.vhd"
printf 'end architecture;\n' >> "$out/cache_map_tb.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/mem_addr_pkg_MiSTer.vhd Zet98/memorymap.vhd "$out/cache_map_tb.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out" cache_map_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" cache_map_tb --assert-level=error --ieee-asserts=disable-at-0
