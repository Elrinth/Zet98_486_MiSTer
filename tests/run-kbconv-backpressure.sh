#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" Zet98/KBIF/KBCONV.vhd tests/kbconv_backpressure_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_backpressure_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_backpressure_tb --assert-level=error --ieee-asserts=disable-at-0
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_backpressure_tb -gDELAYED_READ=true --assert-level=error --ieee-asserts=disable-at-0
# Rebind the converter's component to the actual wire receiver, then exercise
# the same checks using complete start/data/parity/stop frames and host replies.
# Existing KBIF decrements its bounded TIMECNT at zero while simultaneously
# leaving ST_WRSTART1. The value is dead until overwritten, but GHDL rejects
# the assignment (hardware simply truncates it). Suppress ONLY that dead
# decrement in the test copy; leave the production source unchanged.
python3 - "$out/KBIF.vhd" <<'PY'
import pathlib, sys
s=pathlib.Path('PS2IF/KBIF.vhd').read_text()
old="elsif(STATE=ST_WRSTART1)then\n\t\t\t\tif(SFT='1')then\n\t\t\t\t\tTIMECNT<=TIMECNT-1;"
assert s.count(old)==1
s=s.replace(old,old[:-len('TIMECNT<=TIMECNT-1;')]+"if TIMECNT>0 then TIMECNT<=TIMECNT-1;end if;")
pathlib.Path(sys.argv[1]).write_text(s)
PY
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" LIB/PARGEN.vhd "$out/KBIF.vhd"
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_backpressure_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_backpressure_tb -gWIRE_INPUT=true -gDELAYED_READ=true --assert-level=error --ieee-asserts=disable-at-0
# Independent negatives: restoring direct-byte consumption must lose a break;
# removing the publication guard must overwrite the typematic make event.
python3 - "$out" <<'PY'
import pathlib, sys
s=pathlib.Path('Zet98/KBIF/KBCONV.vhd').read_text()
direct=s.replace("if(kb_qpop='1')then", "if(KB_RXED='1')then").replace('kb_qdata=x','KB_RXDAT=x').replace('TBLADR<=kb_qdata;', 'TBLADR<=KB_RXDAT;')
assert direct!=s
guard="\t\t\t\t\t\t-- RXRDY is registered from RXED on the following edge.\n\t\t\t\t\t\t-- Do not mistake that publication cycle for a guest read.\n\t\t\t\t\t\tWAITCNT<=1;"
assert s.count(guard)==1
for name, text in [('direct',direct), ('publication',s.replace(guard,''))]:
 p=pathlib.Path(sys.argv[1])/name;p.mkdir();(p/'KBCONV.vhd').write_text(text)
PY
for mutant in direct publication; do
 work="$out/$mutant"
 ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$work" "$work/KBCONV.vhd" tests/kbconv_backpressure_tb.vhd
 ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$work" kbconv_backpressure_tb
 if ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$work" kbconv_backpressure_tb -gDELAYED_READ=true --assert-level=error --ieee-asserts=disable-at-0 >"$work/result.log" 2>&1; then
  echo "FAIL: $mutant negative unexpectedly passed";exit 1
 fi
 if [ "$mutant" = direct ]; then expected='pending key event missing';else expected='wrong key event: 80 expected 00';fi
 grep -F "$expected" "$work/result.log"
 echo "PASS rejected $mutant negative for the intended event-loss failure"
done
