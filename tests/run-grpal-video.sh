#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed -e 's/entity grpal is/entity grpal_legacy is/' -e 's/end grpal;/end grpal_legacy;/' -e 's/of grpal is/of grpal_legacy is/' tests/reference/grpal_legacy.vhd > "$out/reference.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/reference.vhd" Zet98/grpal.vhd tests/grpal_video_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grpal_video_tb
for mhz in 20 40 50 60 90 100; do
    for phase in 1300 4700 9100; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" grpal_video_tb -gCPU_MHZ="$mhz" -gVIDEO_PHASE_PS="$phase" --assert-level=error --ieee-asserts=disable
    done
done
# Reconnecting the live CPU palette must fail the sampled-video comparison.
sed -e 's/if VIDEO_STAGED generate/if false generate/' -e 's/if not VIDEO_STAGED generate/if true generate/' Zet98/grpal.vhd > "$out/live.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/live.vhd" tests/grpal_video_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grpal_video_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" grpal_video_tb --assert-level=error --ieee-asserts=disable > "$out/negative.log" 2>&1; then
    echo 'FAIL: unstaged palette accepted';exit 1
fi
grep -q 'staged palette differs' "$out/negative.log"
echo 'PASS: live CPU palette negative control rejected'
