#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/knjaddrcnv.vhd \
    Zet98/KNJRAMCONT.vhd Zet98/GAIJIRAMDP.vhd tests/font_tail_ram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_tail_ram_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" font_tail_ram_tb --assert-level=error
python3 - "$out/limited-tail.vhd" <<'PY'
from pathlib import Path
import sys
s=Path('Zet98/GAIJIRAMDP.vhd').read_text()
for port in ('a','b'):
    needle=f'if(address_{port}<(\'0\' & x"6800"))then'
    assert s.count(needle)==1
    s=s.replace(needle, f'if(address_{port}>=(\'0\' & x"1400") and address_{port}<(\'0\' & x"2c00"))then')
Path(sys.argv[1]).write_text(s)
PY
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/limited-tail.vhd" tests/font_tail_ram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_tail_ram_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" font_tail_ram_tb --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: custom-character-only storage passed' >&2; exit 1
fi
grep -q 'Font tail pixel data mismatch at 0' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS: custom-character-only font storage rejected'
