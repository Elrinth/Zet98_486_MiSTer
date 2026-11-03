#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" FDC/headseek.vhd tests/headseek_zero_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" headseek_zero_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" headseek_zero_tb --assert-level=error --ieee-asserts=disable-at-0
# The old engine ended a zero-step seek in the next cycle: it must fail. Rebuild it from this
# one: reach in the ST_IDLE branch again, ST_NOP back to IDLE at once.
sed -e "/^entity headseek4/,\${s/^\([[:space:]]*\)state<=ST_NOP;/\1reach<='1'; state<=ST_NOP;/}" \
    -e "/^entity headseek4/,\${/when ST_NOP =>/,/end if;/{/if(esft='1')then/d;/reach<='1';/d;/end if;/d}}" FDC/headseek.vhd > "$out/old.vhd"
[ "$(grep -c "if(esft='1')then" "$out/old.vhd")" -lt "$(grep -c "if(esft='1')then" FDC/headseek.vhd)" ] || { echo 'FAIL could not recreate the old engine';exit 1; }
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" "$out/old.vhd" tests/headseek_zero_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" headseek_zero_tb
if ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" headseek_zero_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
 echo 'FAIL old engine accepted';exit 1
fi
grep -q 'same-cycle interrupt' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS old engine rejected (zero-step seek ended at once)'
