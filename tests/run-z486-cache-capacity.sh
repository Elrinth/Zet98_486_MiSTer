#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
kind=${1:-instruction}
sizes=(7 8)
asm_flags=()
case "$kind" in
    instruction) varied=ICACHE; fixed=DCACHE; fixed_bits=7; probe=icache_capacity;;
    instruction32) varied=ICACHE; fixed=DCACHE; fixed_bits=7; probe=icache_capacity;
        sizes=(8 9); asm_flags=(-DADD_COUNT=4800);;
    data) varied=DCACHE; fixed=ICACHE; fixed_bits=8; probe=dcache_capacity;;
    *) echo 'Expected instruction, instruction32 or data comparison' >&2; exit 2;;
esac
out=${CACHE_CAPACITY_OUT:-${ICACHE_CAPACITY_OUT:-${DCACHE_CAPACITY_OUT:-}}}
if [[ -z $out ]]; then out=$(mktemp -d); trap 'rm -rf "$out"' EXIT; fi
mkdir -p "$out"
out=$(cd "$out"; pwd)
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
cp rtl/vendor/z486/*.hex "$out/"
for name in "$probe" native_exec native_ddr pegc_cpu stack_allocation deferred_shift_load smc_stream; do
    nasm -f bin "${asm_flags[@]}" "tests/hardware/${name}_probe.asm" -o "$out/$name.bin"
done
for bits in "${sizes[@]}"; do
    verilator --binary --timing -j 3 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU \
        -DZET98_Z486_PIPELINE_REGS=2 -DZET98_NATIVE_DDR -DZET98_NATIVE_DDR_FB_ONLY \
        "-DZET98_Z486_${varied}_SET_BITS=$bits" "-DZET98_Z486_${fixed}_SET_BITS=$fixed_bits" \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 \
        --Mdir "$out/obj-$bits" --top-module z486_xms_resident_tb \
        -GRAM_MB=64 -GPEGC_ENABLE=1 -GDDR_WORDS=16384 -GTRACE_LIMIT=0 \
        -GWATCHDOG_NS=400000000 "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv \
        rtl/graphics/pc98_pegc_bus.sv rtl/graphics/pc98_pegc_control.sv \
        rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
        rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/z486_xms_resident_tb.sv \
        > "$out/compile-$bits.log" 2>&1 || { tail -n 60 "$out/compile-$bits.log"; exit 1; }
    for name in "$probe" native_exec native_ddr pegc_cpu stack_allocation deferred_shift_load smc_stream; do
        (cd "$out"; "./obj-$bits/Vz486_xms_resident_tb" "+program=$out/$name.bin") \
            > "$out/$name-$bits.log" 2>&1 || { tail -n 30 "$out/$name-$bits.log"; exit 1; }
        echo "${varied}_SET_BITS=$bits $name"
        grep -E 'CPU REPORT|RATE |PASS:' "$out/$name-$bits.log"
    done
    verilator --binary --timing -j 3 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -Irtl/vendor/z486 --Mdir "$out/cache-$bits" \
        --top-module z486_pc98_cache_tb "-G${varied}_SET_BITS=$bits" "-G${fixed}_SET_BITS=$fixed_bits" \
        rtl/vendor/z486/z486_cache_map_pkg.sv rtl/vendor/z486/memory.sv \
        rtl/vendor/z486/l1_cache.sv rtl/vendor/z486/l1_icache.sv \
        tests/z486_pc98_cache_tb.sv > "$out/cache-compile-$bits.log" 2>&1 || {
            tail -n 60 "$out/cache-compile-$bits.log"; exit 1;
        }
    "$out/cache-$bits/Vz486_pc98_cache_tb" > "$out/cache-$bits.log" 2>&1 || {
        tail -n 30 "$out/cache-$bits.log"; exit 1;
    }
    cat "$out/cache-$bits.log"
done
python3 - "$out" "$probe" "${sizes[@]}" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
measurements = []
for bits in map(int, sys.argv[3:]):
    log = (root / f'{sys.argv[2]}-{bits}.log').read_text()
    reports = re.findall(r'CPU REPORT .*cycles=(\d+) DDR=(\d+)', log)
    assert len(reports) == 2, reports
    start, end = (tuple(map(int, row)) for row in reports)
    measurements.append((end[0] - start[0], end[1] - start[1]))
assert measurements[0][1] > 0, measurements
assert measurements[1][1] == 0, measurements
assert measurements[1][0] < measurements[0][0], measurements
print(f'PASS: {sys.argv[2]} cycles/DDR {measurements[0]} -> {measurements[1]}')
PY
