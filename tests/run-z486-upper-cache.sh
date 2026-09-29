#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
policy=${PC98_CACHE_POLICY_VERILOG:-/project/build/z486-upper-policy/policy.v}
test -s "$policy"
nasm -f bin tests/ao486_upper_cache.asm -o "$out/program.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
cp rtl/vendor/z486/*.hex "$out/"
for config in 0:0 1:0 1:1 1:2 1:3; do
    upper=${config%:*}; skip=${config#*:}
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
      -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
      -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$upper-$skip" \
      --top-module ao486_upper_cache_tb -GUPPER_RAM_ICACHE="$upper" -GSKIP_INVALIDATION="$skip" \
      "${sources[@]}" "$policy" rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
      rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv \
      rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv tests/ao486_upper_cache_tb.sv \
      > "$out/compile-$config.log" 2>&1 || { tail -n 90 "$out/compile-$config.log"; exit 1; }
    if [ "$skip" = 0 ]; then
        (cd "$out"; "./obj-$upper-$skip/Vao486_upper_cache_tb" "+program=$out/program.bin") | tee "$out/run-$upper.log"
    else
        if (cd "$out"; "./obj-$upper-$skip/Vao486_upper_cache_tb" "+program=$out/program.bin") > "$out/negative-$skip.log" 2>&1; then
            echo "FAIL: disconnected invalidation $skip accepted"; exit 1
        fi
        grep -q 'Upper RAM cache coherence failure' "$out/negative-$skip.log"
        echo "PASS: disconnected invalidation $skip rejected (1 alias / 2 DMA / 3 mapping)"
    fi
done
python3 - "$out" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
r=[tuple(map(int,re.search(r'cycles=(\d+) upper_fetches=(\d+)',(p/f'run-{i}.log').read_text()).groups())) for i in (0,1)]
assert r[1][0] < r[0][0],r
assert r[1][1]*10 < r[0][1],r
print(f'PASS: z486 upper-RAM loop {r[0][0]} -> {r[1][0]} cycles; {r[0][1]} -> {r[1][1]} bus reads')
PY
