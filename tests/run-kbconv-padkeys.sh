#!/usr/bin/env bash
# Gamepad keys injected into KBCONV, plus two negatives: without the open-
# sequence guard a pad key lands inside E0 75; without the table bypass the
# injected code never reaches the guest.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
run() {
 local work=$1 kbconv=$2
 ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$work" "$kbconv" tests/kbconv_backpressure_tb.vhd tests/kbconv_padkeys_tb.vhd
 ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$work" kbconv_padkeys_tb
 ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$work" kbconv_padkeys_tb --assert-level=error --ieee-asserts=disable-at-0
}
run "$out" Zet98/KBIF/KBCONV.vhd | grep -v '(report note): read '
python3 - "$out" <<'PY'
import pathlib, sys
s=pathlib.Path('Zet98/KBIF/KBCONV.vhd').read_text()
guard="elsif(semuen='0' and E0en='0' and F0en='0')then"
mux="TBLDAT<=INJDAT when injsel='1' else E0TBLDAT"
assert s.count(guard)==1 and s.count(mux)==1
for name, text in [('guard', s.replace(guard, "elsif(semuen='0')then")),
                   ('bypass', s.replace(mux, "TBLDAT<=E0TBLDAT"))]:
 p=pathlib.Path(sys.argv[1])/name;p.mkdir();(p/'KBCONV.vhd').write_text(text)
PY
for mutant in guard bypass; do
 work="$out/$mutant"
 if run "$work" "$work/KBCONV.vhd" >"$work/result.log" 2>&1; then
  echo "FAIL: $mutant negative unexpectedly passed";exit 1
 fi
 if [ "$mutant" = guard ]; then expected='pad key reported inside an open E0 sequence';else expected='pending key event missing';fi
 grep -F "$expected" "$work/result.log"
 echo "PASS rejected $mutant negative"
done
