#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Compile the actual framework viewport and multiply/divide implementation.
# Its inherited state machine has no reset. Explicit zero-power-up test
# initialization models the FPGA startup convention, not metastability.
cat > "$out/viewport.sv" <<'EOF'
module viewport(input clk_vid, input LFB_EN,
 input [11:0] LFB_HMIN,LFB_HMAX,LFB_VMIN,LFB_VMAX,
 input [11:0] WIDTH,HEIGHT,HSET,VSET,input FREESCALE,
 input [12:0] ARX,ARY,arc1x,arc1y,arc2x,arc2y);
EOF
tr -d '\r' < MiSTer/sys/sys_top.v |
    sed -n '/^reg \[48:0\] lfb_viewport_meta/,/^`ifndef MISTER_DEBUG_NOHDMI/p' |
    sed '$d' | sed 's/reg  \[2:0\] state;/reg  [2:0] state = 0;/' >> "$out/viewport.sv"
printf '\nendmodule\n' >> "$out/viewport.sv"
grep -q 'if(lfb_viewport_enabled)' "$out/viewport.sv"
run_test() {
    local source=$1 half=$2 target=$3
    iverilog -g2012 -s framebuffer_viewport_tb -Pframebuffer_viewport_tb.SYS_HALF_PS="$half" \
        -o "$out/$target" "$source" MiSTer/sys/math.sv tests/framebuffer_viewport_tb.sv
    vvp "$out/$target"
}
for half in 10000 8333 5556; do
    run_test "$out/viewport.sv" "$half" "test-$half"
done
sed 's/lfb_viewport_video <= lfb_viewport_meta;/lfb_viewport_video <= {LFB_EN,LFB_HMIN,LFB_HMAX,LFB_VMIN,LFB_VMAX};/' \
    "$out/viewport.sv" > "$out/bad.sv"
if run_test "$out/bad.sv" 8333 bad > "$out/bad.log" 2>&1; then
    echo 'ERROR: bypassed framebuffer settings stage accepted'; exit 1
fi
grep -q 'framebuffer settings pipeline mismatch' "$out/bad.log"
echo 'PASS deliberately bypassed framebuffer settings stage rejected'
