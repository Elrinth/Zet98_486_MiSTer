#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 - "$out" <<'PY'
from pathlib import Path
import re
import sys
root=Path(sys.argv[1])
source=Path('Zet98/sdramc.vhd').read_text()
declarations='\n'.join('signal control_'+p.lower()+': job_t;' for p in ('CPU','SUB','FDE','FEC'))
marker='signal\tSUBREQS\t:std_logic;'
assert source.count(marker)==1
for delay in (15,80):
    text=source.replace(marker,declarations+'\n'+marker)
    aliases='\n'.join('    control_'+p.lower()+' <= transport n'+p+'JOB after '+str(delay)+' ns;' for p in ('CPU','SUB','FDE','FEC'))
    marker2='begin\n\n    FDEWAIT'
    assert text.count(marker2)==1
    text=text.replace(marker2,'begin\n'+aliases+'\n\n    FDEWAIT')
    for port in ('CPU','SUB','FDE','FEC'):
        old=port+'JOB<=n'+port+'JOB;'
        shadow='control_'+port.lower()
        # Ignore inherited commented-out assignments in the legacy controller.
        pattern=r'(?m)^([ \t]*)'+re.escape(old)
        text,n=re.subn(pattern,lambda m: m.group(1)+port+'JOB<='+shadow+';\n'+
            '                assert '+shadow+'\'stable(5 ns) report "'+port+' operation arrived too late" severity failure;',text)
        assert n==1,(port,n)
    for port in ('CPU','SUB'):
        marker3='-- '+port+'_READ_COMPLETION_CAPTURE'
        assert text.count(marker3)==1
        text=text.replace(marker3,marker3+'\n'+
            '                    assert '+port.lower()+'end\'stable(20 ns) report "completion synchronization bypassed" severity failure;')
    (root/('control-'+str(delay)+'.vhd')).write_text(text)
    if delay==15:
        for port in ('CPU','SUB'):
            # Break only the consumer, leaving the synchronizer flops present.
            wrong=text.replace(port+'done_sync(1)',port.lower()+'end')
            (root/('bypass-'+port+'.vhd')).write_text(wrong)
PY

ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/control-15.vhd" tests/sdram_request_tb.vhd tests/floppy_sdram_tb.vhd
for bench in sdram_request_tb floppy_sdram_tb; do
    ghdl -e --std=08 -fsynopsys --workdir="$out" "$bench"
    for second in false true; do
        port=USE_SUB; if [ "$bench" = floppy_sdram_tb ]; then port=USE_FEC; fi
        for mhz in 20 40 50 60 90 100; do
            for phase in 0 1300 4700 9100; do
                extra=(); if [ "$bench" = sdram_request_tb ]; then extra=(-gHOLD_COMPLETION_CYCLES=8); else extra=(-gCONTINUOUS=true); fi
                ghdl -r --std=08 -fsynopsys --workdir="$out" "$bench" -gBUFFERED=true -g"$port"="$second" -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" "${extra[@]}" --assert-level=error
            done
        done
    done
done

ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/control-80.vhd" tests/sdram_request_tb.vhd tests/floppy_sdram_tb.vhd
for bench in sdram_request_tb floppy_sdram_tb; do
    ghdl -e --std=08 -fsynopsys --workdir="$out" "$bench"
    for second in false true; do
        port=USE_SUB; if [ "$bench" = floppy_sdram_tb ]; then port=USE_FEC; fi
        if ghdl -r --std=08 -fsynopsys --workdir="$out" "$bench" -gBUFFERED=true -g"$port"="$second" -gCPU_MHZ=100 --assert-level=error > "$out/late.log" 2>&1; then
            echo 'FAIL: late operation bundle accepted'; exit 1
        fi
        grep -Eq 'operation arrived too late|request timed out|unexpected SDRAM|completion mismatch|write data mismatch' "$out/late.log" || { cat "$out/late.log"; exit 1; }
        echo "PASS: late operation bundle rejected $bench $second"
    done
done

for port in CPU SUB; do
    ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/bypass-$port.vhd" tests/sdram_request_tb.vhd
    ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
    second=false; if [ "$port" = SUB ]; then second=true; fi
    if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gBUFFERED=true -gUSE_SUB="$second" -gCPU_MHZ=100 --assert-level=error > "$out/bypass.log" 2>&1; then
        echo 'FAIL: unsynchronized completion accepted'; exit 1
    fi
    grep -q 'completion synchronization bypassed' "$out/bypass.log" || { cat "$out/bypass.log"; exit 1; }
    echo "PASS: unsynchronized completion rejected $port"
done
