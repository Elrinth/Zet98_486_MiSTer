#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Model different routing delays on the two halves of the held payload.
python3 - "$out" <<'PY'
from pathlib import Path
import sys
source=Path('rtl/video_config_snapshot.sv').read_text()
old='assign transfer_data = held_data;'
assert source.count(old)==1
delayed=source.replace(old,'''assign #(`PAYLOAD_DELAY) transfer_data[WIDTH-1:WIDTH/2] = held_data[WIDTH-1:WIDTH/2];
    assign transfer_data[WIDTH/2-1:0] = held_data[WIDTH/2-1:0];''')
directory=Path(sys.argv[1])
(directory/'delayed.sv').write_text('`timescale 1ps/1ps\n'+delayed)
for name,bad in (
    ('busy',source.replace('acknowledge_sync[1] == request && ','')),
    ('bypass',source.replace(old,'assign transfer_data = source_data;')),
    ('early',source.replace('if (request_sync[1] != acknowledge)', 'if (request_sync[0] != acknowledge)').replace('acknowledge <= request_sync[1];','acknowledge <= request_sync[0];'))):
    (directory/(name+'.sv')).write_text(bad)
PY
run_test() {
    local source=$1 sys=$2 video=$3 phase=$4 delay=$5
    iverilog -g2012 -s video_config_snapshot_tb -DPAYLOAD_DELAY="$delay" \
        -Pvideo_config_snapshot_tb.SYS_HALF="$sys" -Pvideo_config_snapshot_tb.VIDEO_HALF="$video" \
        -Pvideo_config_snapshot_tb.PHASE="$phase" -o "$out/test" \
        "$source" tests/video_config_snapshot_tb.sv
    vvp "$out/test"
}
for sys in 25000 12500 10000 8333 5556 5000; do
    for video in 6667 3367 2500; do
        for phase in 0 1 3333 6666; do
            for delay in 0 5000; do
                run_test "$out/delayed.sv" "$sys" "$video" "$phase" "$delay"
            done
        done
    done
done
for bad in busy bypass early; do
    if run_test "$out/$bad.sv" 5000 6667 1 0 > "$out/$bad.log" 2>&1; then
        echo "FAIL: $bad snapshot fault accepted"; exit 1
    fi
    grep -Eq 'snapshot (payload changed|data/order mismatch|capture before)' "$out/$bad.log" || { cat "$out/$bad.log"; exit 1; }
    echo "PASS rejected snapshot fault: $bad"
done
if run_test "$out/delayed.sv" 5000 2500 0 100000 > "$out/late.log" 2>&1; then
    echo 'FAIL: late snapshot data accepted'; exit 1
fi
grep -q 'snapshot data/order mismatch' "$out/late.log"
echo 'PASS rejected snapshot data arriving after capture'
