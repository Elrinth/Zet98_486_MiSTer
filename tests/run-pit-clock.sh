#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 - <<'PY'
from pathlib import Path
s=Path('Zet98/Zet98MiSTer.vhd').read_text()
a=s[s.index('PTCCLK :'):s.index('PTC\t:PTC8253')]
assert 'entity work.pc98_pit_clock generic map(SYSFREQ)' in a
assert '=>PTC_SFT' in a and '=>cpuclk' in a
assert '../../rtl/pc98_pit_clock.vhd' in Path('Zet98/v17/release-Zet98MiSTer.qsf').read_text()
PY
ghdl -a --std=08 -fsynopsys --workdir="$out" LIB/sftclk.vhd rtl/pc98_pit_clock.vhd Zet98/PTC/PTC1ch.vhd Zet98/PTC/PTC8253.vhd tests/pc98_pit_clock_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" pc98_pit_clock_tb
for khz in 20000 50000 75000 90000 100000; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" pc98_pit_clock_tb -gSYSFREQ="$khz" --assert-level=error --ieee-asserts=disable-at-0
done
if ghdl -r --std=08 -fsynopsys --workdir="$out" pc98_pit_clock_tb -gLEGACY=true --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
    echo 'FAIL: half-rate legacy PIT clock accepted'; exit 1
fi
grep -q 'Wrong PIT input rate' "$out/negative.log"
cat "$out/negative.log"
echo 'PASS: legacy half-rate PIT clock rejected'
