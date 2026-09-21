#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ulimit -c 0
# Explicit two-state zero-power-up simulation model for the original no-reset
# OSD. Local explicit zero initializers use the equivalent bit default to
# accommodate Verilator. No control, arithmetic or pipeline logic changes.
sed -E 's/\<reg\>/bit/g; s/^(\t)bit([[:space:]].*) = 0;/\1static bit\2;/' MiSTer/sys/osd.v > "$out/osd.sv"
sed -E 's/\<reg\>/bit/g; s/^(\t)bit([[:space:]].*) = 0;/\1static bit\2;/' tests/reference/osd_legacy.v > "$out/reference.sv"
run_test() {
    local source=$1 half=$2 target=$3
    if command -v verilator >/dev/null; then
        verilator --binary --timing -j 4 -Wno-fatal --x-initial 0 --x-assign 0 \
            --top-module osd_video_tb -GSYS_HALF_PS="$half" --Mdir "$out/$target-obj" \
            "$source" "$out/reference.sv" tests/osd_video_tb.sv > "$out/$target-build.log" 2>&1 || {
                cat "$out/$target-build.log"; return 1;
            }
        "$out/$target-obj/Vosd_video_tb"
    else
        iverilog -g2012 -s osd_video_tb -Posd_video_tb.SYS_HALF_PS="$half" \
            -o "$out/$target" "$source" "$out/reference.sv" tests/osd_video_tb.sv
        vvp "$out/$target"
    fi
}
for half in 10000 8333; do
    run_test "$out/osd.sv" "$half" "test-$half"
done
sed 's/osd_config_video <= osd_config_meta;/osd_config_video <= {osd_enable, info, infoh, infow, infox, infoy, osd_h, osd_t, osd_w, rot};/' \
    "$out/osd.sv" > "$out/bad.sv"
if run_test "$out/bad.sv" 8333 bad > "$out/bad.log" 2>&1; then
    echo 'ERROR: bypassed menu settings stage was accepted'; exit 1
fi
grep -q 'menu settings pipeline mismatch' "$out/bad.log"
echo 'PASS deliberately bypassed menu settings stage rejected'
