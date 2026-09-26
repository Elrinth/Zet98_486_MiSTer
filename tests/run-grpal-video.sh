#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed -e 's/entity grpal is/entity grpal_legacy is/' -e 's/end grpal;/end grpal_legacy;/' -e 's/of grpal is/of grpal_legacy is/' tests/reference/grpal_legacy.vhd > "$out/reference.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/reference.vhd" rtl/reset_release.vhd Zet98/grpal.vhd tests/grpal_video_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grpal_video_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" grpal_video_tb --assert-level=error --ieee-asserts=disable
# Exercise the full SDC payload bound; controls keep their real RTL latency.
sed 's/palette_transfer <= palette_hold;/palette_transfer <= transport palette_hold after 20 ns;/' Zet98/grpal.vhd > "$out/delayed.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/delayed.vhd" tests/grpal_video_tb.vhd
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
grep -q 'palette changed between video edges' "$out/negative.log"
echo 'PASS: live CPU palette negative control rejected'
# Late payload must fail: a quiet last write cannot be lost indefinitely.
sed 's/palette_transfer <= palette_hold;/palette_transfer <= transport palette_hold after 60 ns;/' Zet98/grpal.vhd > "$out/late.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/late.vhd" tests/grpal_video_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grpal_video_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" grpal_video_tb --assert-level=error --ieee-asserts=disable > "$out/late.log" 2>&1; then
    echo 'FAIL: late palette payload accepted';exit 1
fi
grep -q 'palette snapshot lost final update' "$out/late.log" || { cat "$out/late.log";exit 1; }
echo 'PASS: late palette payload negative control rejected'
# Check the actual payload remains stable for >=20 ns after video capture
# (two CPU periods at the maximum tested 100 MHz). This is the handshake
# condition needed to exclude unrelated nominal-edge hold checks in STA.
python3 tests/instrument_palette_hold.py "$out/held.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/held.vhd" tests/grpal_video_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grpal_video_tb
for mhz in 20 40 50 60 90 100; do
    for phase in 1300 4700 9100; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" grpal_video_tb -gCPU_MHZ="$mhz" -gVIDEO_PHASE_PS="$phase" --assert-level=error --ieee-asserts=disable
    done
done
# Bypassing the return synchronizer allows the next CPU edge to change the
# payload too soon. The temporal observer, not the final-palette comparison,
# must reject this deliberately broken handshake.
sed 's/palette_request=ack_sync(1)/palette_request=palette_ack/' "$out/held.vhd" > "$out/early-release.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/early-release.vhd" tests/grpal_video_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grpal_video_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" grpal_video_tb -gCPU_MHZ=100 --assert-level=error --ieee-asserts=disable > "$out/early-release.log" 2>&1; then
    echo 'FAIL: early palette release accepted';exit 1
fi
grep -q 'palette payload changed inside post-capture hold window' "$out/early-release.log" || { cat "$out/early-release.log";exit 1; }
echo 'PASS: post-capture payload hold window and early-release negative control'
