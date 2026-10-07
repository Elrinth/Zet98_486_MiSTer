#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s ao486_io_bridge_tb -o "$out/io.vvp" \
    rtl/cpu/ao486_io_bridge.sv tests/ao486_io_bridge_tb.sv
vvp "$out/io.vvp"
bash tests/run-memory-mask-contract.sh
bash tests/run-decode-buffer.sh
bash tests/run-extmem-bridge.sh
bash tests/run-sdram.sh
bash tests/run-sdram-write-bundle.sh
bash tests/run-sub-write-bundle.sh
bash tests/run-sdram-read-bundle.sh
bash tests/run-floppy-sdram.sh
bash tests/run-floppy-events.sh
bash tests/run-floppy-read-bundle.sh
bash tests/run-video-sdram.sh
bash tests/run-video-settings.sh
bash tests/run-graphics-address.sh
bash tests/run-text-pixel-memory.sh
bash tests/run-font-address.sh
bash tests/run-font-tail.sh
bash tests/run-video-counters.sh
bash tests/run-video-config-snapshot.sh
bash tests/run-video-scale.sh
bash tests/run-video-calc.sh
bash tests/run-framebuffer-viewport.sh
bash tests/run-hdmi-tune-gate.sh
bash tests/run-video-status.sh
bash tests/run-lowmem-cache.sh
ghdl -a --std=08 -fsynopsys --workdir="$out" \
    LIB/sftgen.vhd rtl/opna_clock_enable.vhd LIB/sftclk.vhd LIB/fixtimer.vhd tests/peripheral_rates_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=50000 --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=60000 --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=75000 --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=90000 --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=100000 --assert-level=error
bash tests/run-pic.sh
ghdl -a --std=08 --workdir="$out" VIDEO/text_row_counter.vhd tests/text_row_counter_tb.vhd
ghdl -e --std=08 --workdir="$out" text_row_counter_tb
ghdl -r --std=08 --workdir="$out" text_row_counter_tb --assert-level=error
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/VTIMING.vhd tests/video_line_timing_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" video_line_timing_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" video_line_timing_tb --assert-level=error
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/synccont2.vhd rtl/video_retrace_cdc.vhd tests/video_retrace_cdc_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" video_retrace_cdc_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" video_retrace_cdc_tb --assert-level=error
iverilog -g2012 -Wall -s video_output_tb -o "$out/video.vvp" rtl/video_output.sv tests/video_output_tb.sv
vvp "$out/video.vvp"
bash tests/run-floppy-overlay.sh
bash tests/run-crtc-reset.sh
bash tests/run-crtc-compositor.sh
bash tests/run-disk-interface.sh
bash tests/run-ide.sh
bash tests/run-data-bus.sh
bash tests/run-grcg-compare.sh
bash tests/run-grcg-alias.sh
bash tests/run-grcg-sdram.sh
bash tests/run-egc-rop.sh
bash tests/run-egc-registers.sh
bash tests/run-rmw-plane-alignment.sh
bash tests/run-egc-memory.sh
bash tests/run-egc-shift.sh
bash tests/run-egc-write.sh
bash tests/run-egc-engine.sh
bash tests/run-cache-map.sh
bash tests/run-pcm86.sh
bash tests/run-audio-decimator.sh
bash tests/run-alsa-gain.sh
bash tests/run-snac-psx.sh
bash tests/run-stick-mouse.sh
bash tests/run-atapi.sh
bash tests/run-opna-timer.sh
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/DMA/DMASW.vhd tests/dma_grant_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" dma_grant_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" dma_grant_tb --assert-level=error
bash tests/run-dma-byte-pointer.sh
bash tests/run-dma-terminal-count.sh
ghdl -a --std=08 --workdir="$out" rtl/startup_mute.vhd tests/startup_mute_tb.vhd
ghdl -e --std=08 --workdir="$out" startup_mute_tb
ghdl -r --std=08 --workdir="$out" startup_mute_tb --assert-level=error

bash tests/run-video-reset.sh
