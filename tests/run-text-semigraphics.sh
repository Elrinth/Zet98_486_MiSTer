#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd VIDEO/text_row_counter.vhd Zet98/knjaddrcnv.vhd VIDEO/font_prefetch.vhd VIDEO/knjscr.vhd tests/text_semigraphics_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" text_semigraphics_tb
for height in 8 16; do
 for wide in false true; do
  for delay in 0 12 25; do
   ghdl -r --std=08 -fsynopsys --workdir="$out" text_semigraphics_tb -gHEIGHT="$height" -gWIDE="$wide" -gRAM_DELAY_NS="$delay" --assert-level=error --ieee-asserts=disable-at-0
  done
 done
done
python3 - "$out/old.vhd" <<'PY'
from pathlib import Path
import sys
s=Path('VIDEO/knjscr.vhd').read_text()
a="attribute_mode_pixel<=ATRSEL;"
assert s.count(a)==1
Path(sys.argv[1]).write_text(s.replace(a,"attribute_mode_pixel<='0';"))
PY
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/old.vhd" tests/text_semigraphics_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" text_semigraphics_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" text_semigraphics_tb --assert-level=error > "$out/old.log" 2>&1; then
 echo 'FAIL old attribute interpretation accepted'; exit 1
fi
grep -q 'Semigraphics pixel mismatch trial=0' "$out/old.log"
echo 'PASS old vertical-line interpretation rejected for blank code0/attributeF1'
