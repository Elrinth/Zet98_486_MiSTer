#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Compile the actual framework viewport and multiply/divide implementation.
# Its inherited state machine has no reset. Explicit zero-power-up test
# initialization models the FPGA startup convention, not metastability.
cat > "$out/viewport.sv" <<'EOF'
module viewport(input clk_vid,clk_sys, input LFB_EN,
 input [11:0] LFB_HMIN,LFB_HMAX,LFB_VMIN,LFB_VMAX,
 input [11:0] WIDTH,HEIGHT,HSET,VSET,input FREESCALE,
 input [12:0] ARX,ARY,arc1x,arc1y,arc2x,arc2y);
EOF
tr -d '\r' < MiSTer/sys/sys_top.v |
    sed -n '/^wire \[149:0\] viewport_config_video/,/^`ifndef MISTER_DEBUG_NOHDMI/p' |
    sed '$d' | sed 's/reg  \[2:0\] state;/reg  [2:0] state = 0;/' >> "$out/viewport.sv"
printf '\nendmodule\n' >> "$out/viewport.sv"
grep -q 'if(lfb_viewport_enabled)' "$out/viewport.sv"
run_test() {
    local source=$1 half=$2 target=$3
    iverilog -g2012 -s framebuffer_viewport_tb -Pframebuffer_viewport_tb.SYS_HALF_PS="$half" \
        -o "$out/$target" "$source" rtl/video_config_snapshot.sv MiSTer/sys/math.sv tests/framebuffer_viewport_tb.sv
    vvp "$out/$target"
}
for half in 10000 8333 5556; do
    run_test "$out/viewport.sv" "$half" "test-$half"
done
python3 - "$out/viewport.sv" "$out/bad.sv" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]).read_text()
p=p.replace('.video_data(viewport_config_video)', '.video_data()')
p=p.replace('wire [149:0] viewport_config_video;', 'wire [149:0] viewport_config_video = {LFB_EN,LFB_HMIN,LFB_HMAX,LFB_VMIN,LFB_VMAX,\n FREESCALE,HSET,VSET,WIDTH,HEIGHT,arc1x,arc1y,arc2x,arc2y};')
Path(sys.argv[2]).write_text(p)
PY
if run_test "$out/bad.sv" 8333 bad > "$out/bad.log" 2>&1; then
    echo 'ERROR: unacknowledged framebuffer settings accepted'; exit 1
fi
grep -q 'framebuffer settings snapshot mismatch' "$out/bad.log"
echo 'PASS deliberately unacknowledged framebuffer settings rejected'
