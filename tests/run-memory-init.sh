#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
intel_lib=${INTEL_SIM_LIB:-/project/build/intel-sim}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed -e "s/\.wren_a(memory_we\[i\])/\.wren_a(memory_we[i] \& 1'b1)/" \
    -e "s/\.byteena_a(memory_be)/\.byteena_a(memory_be | 4'b0)/" \
    -e "s/(CLK)/(CLK \& 1'b1)/g" rtl/vendor/cache/l1_icache.v > "$out/l1_icache.v"
sed -e "s/(clk)/(clk \& 1'b1)/g" rtl/vendor/common/simple_fifo_mlab.v > "$out/simple_fifo_mlab.v"
mapfile -t sources < <(sed -n 's@.*qip_path) \([^ ]*\.v\) .*@rtl/vendor/ao486/\1@p' rtl/vendor/ao486/ao486.qip)
for ram in 0 16 64; do
    nasm -Isoftware/ -DTOP_MB="$ram" -DSIM=1 -f bin software/z98mem.asm -o "$out/init.bin"
    iverilog -g2012 -I rtl/vendor/ao486 -s ao486_extmem_tb -Pao486_extmem_tb.RAM_MB="$ram" \
        -Pao486_extmem_tb.DOS_PROBE=1 -Pao486_extmem_tb.MEMORY_INIT=1 -Pao486_extmem_tb.LOWMEM_CACHE=1 \
        -o "$out/cpu.vvp" "${sources[@]}" "$out/l1_icache.v" "$out/simple_fifo_mlab.v" \
        rtl/vendor/common/simple_mult.v rtl/cpu/*.sv tests/cpu_export.sv tests/ao486_extmem_tb.sv \
        "$intel_lib/altera_mf.v" 2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
    vvp "$out/cpu.vvp" "+program=$out/init.bin"
done
