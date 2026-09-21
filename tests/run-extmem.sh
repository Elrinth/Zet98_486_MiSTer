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
for test in instructions dos-probe; do
for ram in 16 64; do
    probe=0
    program=tests/ao486_extmem.asm
    if [[ "$test" == dos-probe ]]; then probe=1; program=tests/hardware/ram_probe.asm; fi
    nasm -DTOP_MB="$ram" -DSIM=1 -f bin "$program" -o "$out/ram.bin"
    iverilog -g2012 -I rtl/vendor/ao486 -s ao486_extmem_tb -Pao486_extmem_tb.RAM_MB="$ram" \
        -Pao486_extmem_tb.DOS_PROBE="$probe" -Pao486_extmem_tb.LOWMEM_CACHE="${LOWMEM_CACHE:-0}" \
        -o "$out/cpu.vvp" "${sources[@]}" "$out/l1_icache.v" "$out/simple_fifo_mlab.v" \
        rtl/vendor/common/simple_mult.v rtl/cpu/*.sv tests/cpu_export.sv tests/ao486_extmem_tb.sv \
        "$intel_lib/altera_mf.v" 2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
    vvp "$out/cpu.vvp" "+program=$out/ram.bin"
done
done
# A 64 MB probe must reject an implementation with only the 16 MB map.
nasm -DTOP_MB=64 -DSIM=1 -f bin tests/hardware/ram_probe.asm -o "$out/ram.bin"
iverilog -g2012 -I rtl/vendor/ao486 -s ao486_extmem_tb -Pao486_extmem_tb.RAM_MB=16 \
    -Pao486_extmem_tb.DOS_PROBE=1 -Pao486_extmem_tb.LOWMEM_CACHE="${LOWMEM_CACHE:-0}" -o "$out/negative.vvp" "${sources[@]}" \
    "$out/l1_icache.v" "$out/simple_fifo_mlab.v" rtl/vendor/common/simple_mult.v \
    rtl/cpu/*.sv tests/cpu_export.sv tests/ao486_extmem_tb.sv "$intel_lib/altera_mf.v" \
    2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
if vvp "$out/negative.vvp" "+program=$out/ram.bin" >"$out/negative.log" 2>&1; then
    echo 'FAIL: 64 MB diagnostic accepted a 16 MB implementation'; exit 1
fi
grep -q 'protected-mode extended memory program failed' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS: 64 MB diagnostic rejects the 16 MB negative control'
