#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
intel_lib=${INTEL_SIM_LIB:-/project/build/intel-sim}
test -f "$intel_lib/altera_mf.v" || { echo "Set INTEL_SIM_LIB to the installed Quartus eda/sim_lib directory" >&2; exit 1; }
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/ao486_smoke.asm -o "$out/smoke.bin"
# Icarus 11 propagates Intel model tri0/tri1 input defaults back into connected
# procedural registers. Isolate those inputs with identity expressions in
# temporary simulation copies; synthesis and the vendored originals are intact.
sed -e "s/\.wren_a(memory_we\[i\])/\.wren_a(memory_we[i] \& 1'b1)/" \
    -e "s/\.byteena_a(memory_be)/\.byteena_a(memory_be | 4'b0)/" \
    -e "s/(CLK)/(CLK \& 1'b1)/g" rtl/vendor/cache/l1_icache.v > "$out/l1_icache.v"
sed -e "s/(clk)/(clk \& 1'b1)/g" rtl/vendor/common/simple_fifo_mlab.v > "$out/simple_fifo_mlab.v"
mapfile -t sources < <(sed -n 's@.*qip_path) \([^ ]*\.v\) .*@rtl/vendor/ao486/\1@p' rtl/vendor/ao486/ao486.qip)
iverilog -g2012 -I rtl/vendor/ao486 -s ao486_cpu_tb -Pao486_cpu_tb.LOWMEM_CACHE="${LOWMEM_CACHE:-0}" -o "$out/cpu.vvp" \
    "${sources[@]}" "$out/l1_icache.v" "$out/simple_fifo_mlab.v" \
    rtl/vendor/common/simple_mult.v rtl/cpu/*.sv tests/cpu_export.sv tests/ao486_cpu_tb.sv "$intel_lib/altera_mf.v"
vvp "$out/cpu.vvp" "+program=$out/smoke.bin" "$@"
