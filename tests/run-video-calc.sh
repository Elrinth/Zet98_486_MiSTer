#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
tr -d '\r' < MiSTer/sys/hps_io.sv | sed -n '/^module video_calc$/,/^endmodule$/p' > "$out/video_calc.sv"
for half in 25000 10000 8333 5556; do
    iverilog -g2012 -s video_calc_tb -Pvideo_calc_tb.SYS_HALF_PS="$half" -o "$out/test" "$out/video_calc.sv" rtl/video_config_snapshot.sv tests/video_calc_tb.sv
    vvp "$out/test"
done
