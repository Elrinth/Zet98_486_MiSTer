#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for queue in 0 3; do
    for early in 0 1; do
        iverilog -g2012 -I rtl/vendor/ao486 -s ao486_memory_integration_tb \
            -Pao486_memory_integration_tb.EARLY_MEMORY_GRANT="$early" \
            -Pao486_memory_integration_tb.MEMORY_QUEUE_BITS="$queue" \
            -o "$out/integration" rtl/vendor/ao486/memory/avalon_mem.v \
            rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
            rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv tests/ao486_memory_integration_tb.sv
        vvp "$out/integration" | tee "$out/$early.log"
    done
    before=$(sed -n 's/^integration_cycles=//p' "$out/0.log")
    after=$(sed -n 's/^integration_cycles=//p' "$out/1.log")
    [[ -n $before && -n $after && $after -lt $before ]] || {
        echo 'FAIL: early grant did not shorten the checked workload'; exit 1;
    }
    echo "PASS early grant queue=$queue: $before -> $after clocks"
done
# Reject an idle-grant shortcut that steals an active I/O owner's bus.
sed 's/wire memory_granted = owner == MEMORY;/wire memory_granted = owner == MEMORY || owner == IO;/' \
    rtl/cpu/ao486_bus_bridge.sv > "$out/bad-owner.sv"
iverilog -g2012 -I rtl/vendor/ao486 -s ao486_memory_integration_tb \
    -o "$out/bad-owner" rtl/vendor/ao486/memory/avalon_mem.v \
    rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
    rtl/cpu/ao486_memory_queue.sv "$out/bad-owner.sv" tests/ao486_memory_integration_tb.sv
if vvp "$out/bad-owner" > "$out/bad-owner.log" 2>&1; then
    echo 'FAIL: active-owner arbitration mutation passed'; exit 1
fi
grep -q 'memory command accepted while I/O owns the bus' "$out/bad-owner.log"
echo 'PASS: active-owner arbitration mutation rejected'
# Includes native and fallback reads canceled across a CPU reset. An accepted
# DDR response must drain before the idle-bus shortcut admits a new command.
for early in 0 1; do
    for ram in 0 1; do
        iverilog -g2012 -i -s pc98_native_router_tb \
            -Ppc98_native_router_tb.EARLY_MEMORY_GRANT="$early" \
            -Ppc98_native_router_tb.RAM_ENABLE="$ram" -o "$out/router" \
            rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
            rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
            rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_ao486.sv \
            rtl/graphics/pc98_pegc_control.sv rtl/graphics/pc98_pegc_bus.sv \
            rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
            rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_native_router_tb.sv
        vvp "$out/router"
    done
done
