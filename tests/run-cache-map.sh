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
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/mem_addr_pkg_MiSTer.vhd Zet98/memorymap.vhd rtl/cpu/pc98_cache_policy.vhd "$out/cache_map_tb.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out" cache_map_tb
for upper in 0 1; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" cache_map_tb -gUPPER_RAM_ICACHE="$upper" --assert-level=error --ieee-asserts=disable-at-0
done
# A widened bank match aliases peripheral banks into the invalidation range.
# The independent mapper comparison must reject it.
sed 's/7 downto 3)="00000"/7 downto 4)="0000"/g' rtl/cpu/pc98_cache_policy.vhd > "$out/bad-map.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/bad-map.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/cache_map_tb.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out" cache_map_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" cache_map_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
    echo 'FAIL: widened bank decode was accepted'; exit 1
fi
grep -q 'Wrong RAM alias invalidation' "$out/negative.log"
echo 'PASS: widened bank decode rejected'
