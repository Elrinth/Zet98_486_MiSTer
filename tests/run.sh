#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s ao486_io_bridge_tb -o "$out/io.vvp" \
    rtl/cpu/ao486_io_bridge.sv tests/ao486_io_bridge_tb.sv
vvp "$out/io.vvp"
bash tests/run-memory-bridge.sh
bash tests/run-decode-buffer.sh
iverilog -g2012 -Wall -I rtl/vendor/ao486 -s ao486_memory_integration_tb \
    -o "$out/memory-integration.vvp" rtl/vendor/ao486/memory/avalon_mem.v \
    rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
    rtl/cpu/ao486_bus_bridge.sv tests/ao486_memory_integration_tb.sv
vvp "$out/memory-integration.vvp"
bash tests/run-extmem-bridge.sh
bash tests/run-sdram.sh
bash tests/run-sdram-write-bundle.sh
bash tests/run-sub-write-bundle.sh
bash tests/run-sdram-read-bundle.sh
bash tests/run-floppy-sdram.sh
bash tests/run-video-sdram.sh
bash tests/run-graphics-address.sh
bash tests/run-text-pixel-memory.sh
bash tests/run-video-counters.sh
bash tests/run-video-scale.sh
bash tests/run-video-calc.sh
bash tests/run-framebuffer-viewport.sh
bash tests/run-hdmi-tune-gate.sh
bash tests/run-lowmem-cache.sh
ghdl -a --std=08 -fsynopsys --workdir="$out" \
    LIB/sftgen.vhd LIB/sftclk.vhd LIB/fixtimer.vhd tests/peripheral_rates_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=50000 --assert-level=error
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=60000 --assert-level=error
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/z8259.vhd tests/pc98_pic_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" pc98_pic_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" pc98_pic_tb --assert-level=error
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
bash tests/run-cache-map.sh
bash tests/run-pcm86.sh
bash tests/run-opna-timer.sh
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/DMA/DMASW.vhd tests/dma_grant_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" dma_grant_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" dma_grant_tb --assert-level=error
ghdl -a --std=08 --workdir="$out" rtl/startup_mute.vhd tests/startup_mute_tb.vhd
ghdl -e --std=08 --workdir="$out" startup_mute_tb
ghdl -r --std=08 --workdir="$out" startup_mute_tb --assert-level=error

bash tests/run-video-reset.sh
