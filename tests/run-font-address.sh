#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/knjaddrcnv.vhd Zet98/KNJRAMCONT.vhd tests/font_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_address_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" font_address_tb --assert-level=error

# Reintroduce the original half-selector bug in a temporary copy. The same
# controller-level test must reject it, not merely agree with the new code.
sed 's/kcode[[:space:]]*=>CGCODE,/kcode =>not CPOS(5) \& JISCODE(14 downto 0),/' \
    Zet98/KNJRAMCONT.vhd > "$out/bad-font.vhd"
grep -q 'kcode =>not CPOS(5)' "$out/bad-font.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/bad-font.vhd" tests/font_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_address_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" font_address_tb --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: original ASCII half-selector bug passed' >&2; exit 1
fi
grep -q 'ASCII font read selected a Kanji glyph for Start' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS: original ASCII font-address bug rejected'

python3 - "$out/bad-converter.vhd" <<'PY'
from pathlib import Path
import sys
s=Path('Zet98/knjaddrcnv.vhd').read_text()
assert s.count('if(mcode<x"0c00")then') == 1
s=s.replace('if(mcode<x"0c00")then', 'if(mcode<x"0900")then')
needle='\t\telse\n\t\t\ttmpl:='
assert s.count(needle) == 1
s=s.replace(needle, '\t\telsif(mcode<x"0c00")then\n\t\t\taddr<=x"03a0" + (mcode-x"0c00");\n'+needle)
Path(sys.argv[1]).write_text(s)
PY
# Restore the good controller so this negative control isolates the mapper.
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/bad-converter.vhd" Zet98/KNJRAMCONT.vhd tests/font_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_address_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" font_address_tb --assert-level=error > "$out/bad-mapper.log" 2>&1; then
    echo 'FAIL: original JIS row 09..0b mapping passed' >&2; exit 1
fi
grep -q 'Rusty row09 S selected the wrong FONT.ROM glyph' "$out/bad-mapper.log" || { cat "$out/bad-mapper.log"; exit 1; }
echo 'PASS: original JIS row 09..0b mapping bug rejected'

# Independently restore the loader's old 256-KiB limit and two-bank select.
python3 - "$out/bad-loader.vhd" <<'PY'
from pathlib import Path
import sys
s=Path('Zet98/KNJRAMCONT.vhd').read_text()
assert s.count('FONT_OFFSET(18 downto 17)') == 1
assert s.count('LDR_EXTADDR<=ENDADDR') == 1
s=s.replace('FONT_OFFSET(18 downto 17)', "'0' & FONT_OFFSET(17)")
s=s.replace('LDR_EXTADDR<=ENDADDR', 'LDR_EXTADDR<x"080000"')
Path(sys.argv[1]).write_text(s)
PY
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/knjaddrcnv.vhd "$out/bad-loader.vhd" tests/font_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_address_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" font_address_tb --assert-level=error > "$out/bad-loader.log" 2>&1; then
    echo 'FAIL: original two-bank loader passed' >&2; exit 1
fi
grep -q 'Font loader lost a bank boundary or the third bank' "$out/bad-loader.log" || { cat "$out/bad-loader.log"; exit 1; }
echo 'PASS: original two-bank font loader rejected'
