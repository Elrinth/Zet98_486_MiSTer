#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
bash tests/run-extmem-bridge.sh
for narrow in 0 1; do
    for dword in 0 1; do
        iverilog -g2012 -s ao486_memory_bridge_tb \
            -Pao486_memory_bridge_tb.NARROW_READS="$narrow" \
            -Pao486_memory_bridge_tb.RAM_DWORD_READ="$dword" -o "$out/bridge" \
            rtl/cpu/ao486_memory_bridge.sv tests/ao486_memory_bridge_tb.sv
        vvp "$out/bridge" | tee "$out/bridge-$dword.log"
    done
    before=$(sed -n 's/^memory_bridge_cycles=//p' "$out/bridge-0.log")
    after=$(sed -n 's/^memory_bridge_cycles=//p' "$out/bridge-1.log")
    [[ $after -lt $before ]] || { echo 'FAIL: DWORD reads did not save cycles'; exit 1; }
    echo "PASS: narrow=$narrow DWORD reads reduce $before to $after clocks"
done
# A wrong DWORD lane can leave the legacy halfword result correct.
sed 's/assign dword_data = address\[2\] ?/assign dword_data = !address[2] ?/' \
    rtl/cpu/pc98_extmem_bridge.sv > "$out/wrong-dword.sv"
iverilog -g2012 -s pc98_extmem_bridge_tb -o "$out/wrong-dword" \
    "$out/wrong-dword.sv" tests/pc98_extmem_bridge_tb.sv
if vvp "$out/wrong-dword" > "$out/negative.log" 2>&1; then
    echo 'FAIL: wrong DWORD lane mutation passed'; exit 1
fi
grep -q 'incorrect buffered DWORD data' "$out/negative.log"
echo 'PASS: wrong DWORD lane rejected'
for dword in 0 1; do
    for native_ram in 0 1; do
        iverilog -g2012 -i -s pc98_native_router_tb \
            -Ppc98_native_router_tb.EXT_RAM_DWORD_READ="$dword" \
            -Ppc98_native_router_tb.RAM_ENABLE="$native_ram" -o "$out/router" \
            rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
            rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
            rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_ao486.sv \
            rtl/graphics/pc98_pegc_control.sv rtl/graphics/pc98_pegc_bus.sv \
            rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
            rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_native_router_tb.sv
        vvp "$out/router"
    done
done
bash tests/run-early-memory-grant.sh
