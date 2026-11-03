#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 --workdir="$out" VIDEO/text_row_counter.vhd tests/text_scroll_tb.vhd
ghdl -e --std=08 --workdir="$out" text_scroll_tb
ghdl -r --std=08 --workdir="$out" text_scroll_tb --assert-level=error

# The unscrolled counter (SSL ignored) must be rejected.
python3 - "$out/bad-skip.vhd" <<'PY'
from pathlib import Path
import sys
s=Path('VIDEO/text_row_counter.vhd').read_text()
old="if ssl < char_lines then first := ssl; else first := 0; end if;"
assert s.count(old) == 1
Path(sys.argv[1]).write_text(s.replace(old, "first := 0;"))
PY
ghdl -a --std=08 --workdir="$out" "$out/bad-skip.vhd" tests/text_scroll_tb.vhd
ghdl -e --std=08 --workdir="$out" text_scroll_tb
if ghdl -r --std=08 --workdir="$out" text_scroll_tb --assert-level=error > "$out/bad-skip.log" 2>&1; then
    echo 'FAIL: a counter without the smooth scroll passed' >&2; exit 1
fi
grep -q 'NP2kai line' "$out/bad-skip.log" || { cat "$out/bad-skip.log"; exit 1; }
echo 'PASS: counter without the smooth scroll rejected'

# The row after the region starts over without advancing the text row.
python3 - "$out/bad-tail.vhd" <<'PY'
from pathlib import Path
import sys
s=Path('VIDEO/text_row_counter.vhd').read_text()
old="row <= 0; phase <= BELOW;"
assert s.count(old) == 1
Path(sys.argv[1]).write_text(s.replace(old, "row <= 0; adv <= '1'; phase <= BELOW;"))
PY
ghdl -a --std=08 --workdir="$out" "$out/bad-tail.vhd" tests/text_scroll_tb.vhd
ghdl -e --std=08 --workdir="$out" text_scroll_tb
if ghdl -r --std=08 --workdir="$out" text_scroll_tb --assert-level=error > "$out/bad-tail.log" 2>&1; then
    echo 'FAIL: advancing the row at the region end passed' >&2; exit 1
fi
grep -q 'NP2kai line' "$out/bad-tail.log" || { cat "$out/bad-tail.log"; exit 1; }
echo 'PASS: advancing the row at the region end rejected'
