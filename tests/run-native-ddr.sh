#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for ram in 0 16 64; do
    iverilog -g2012 -s native_route_decode_tb -Pnative_route_decode_tb.RAM_MB="$ram" \
        -o "$out/decode" rtl/cpu/ao486_memory_bridge.sv tests/native_route_decode_tb.sv
    vvp "$out/decode"
done
iverilog -g2012 -s native_route_decode_tb -Pnative_route_decode_tb.RAM_ENABLE=0 \
    -o "$out/decode-fb" rtl/cpu/ao486_memory_bridge.sv tests/native_route_decode_tb.sv
vvp "$out/decode-fb"
for latency in 0 1 7 37; do
    iverilog -g2012 -s pc98_native_ddr_tb -Ppc98_native_ddr_tb.LATENCY="$latency" \
        -o "$out/native" rtl/cpu/pc98_extmem_bridge.sv tests/pc98_native_ddr_tb.sv
    vvp "$out/native"
done
# -i deliberately leaves the CPU black box unelaborated: this bench drives
# its Avalon interface, while the separate z486 test runs real instructions.
for ram_enable in 0 1; do
iverilog -g2012 -i -s pc98_native_router_tb -Ppc98_native_router_tb.RAM_ENABLE="$ram_enable" -o "$out/router" \
    rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
    rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_ao486.sv \
    rtl/graphics/pc98_pegc_control.sv rtl/graphics/pc98_pegc_bus.sv \
    rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
    rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_native_router_tb.sv
vvp "$out/router"
done
