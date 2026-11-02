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
# The BIOS code range (E0000h-FFFFFh) is instruction-cached by z486 memory.sv;
# the last configuration compiles a copy without it.
mkdir -p "$out/nobios"
cp -r rtl/vendor/z486/. "$out/nobios/"
sed -i "s/(icache_req_phys_addr >= 32'h000e_0000 \&\&/(1'b0 \&\& icache_req_phys_addr >= 32'h000e_0000 \&\&/" "$out/nobios/memory.sv"
grep -q "(1'b0 && icache_req_phys_addr >= 32'h000e_0000" "$out/nobios/memory.sv"
# upper:skip:bios
for config in 0:0:1 1:0:1 1:1:1 1:2:1 1:3:1 1:0:0; do
    upper=${config%%:*}; rest=${config#*:}; skip=${rest%%:*}; bios=${rest#*:}
    zdir=rtl/vendor/z486
    if [ "$bios" = 0 ]; then zdir="$out/nobios"; fi
    zsources=("${sources[@]/#rtl\/vendor\/z486/$zdir}")
    obj="$out/obj-$upper-$skip-$bios"
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
      -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
      -I"$zdir" -I"$zdir/x87" --Mdir "$obj" \
      --top-module ao486_upper_cache_tb -GUPPER_RAM_ICACHE="$upper" -GSKIP_INVALIDATION="$skip" -GBIOS_ICACHE="$bios" \
      "${zsources[@]}" "$policy" rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
      rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv \
      rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv tests/ao486_upper_cache_tb.sv \
      > "$out/compile-$upper-$skip-$bios.log" 2>&1 || { tail -n 90 "$out/compile-$upper-$skip-$bios.log"; exit 1; }
    if [ "$skip" = 0 ]; then
        (cd "$out"; "$obj/Vao486_upper_cache_tb" "+program=$out/program.bin") | tee "$out/run-$upper-$bios.log"
    else
        if (cd "$out"; "$obj/Vao486_upper_cache_tb" "+program=$out/program.bin") > "$out/negative-$skip.log" 2>&1; then
            echo "FAIL: disconnected invalidation $skip accepted"; exit 1
        fi
        grep -q 'Upper RAM cache coherence failure' "$out/negative-$skip.log"
        echo "PASS: disconnected invalidation $skip rejected (1 alias / 2 DMA / 3 mapping)"
    fi
done
python3 - "$out" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
r=[tuple(map(int,re.search(r'cycles=(\d+) upper_fetches=(\d+)',(p/f'run-{i}-1.log').read_text()).groups())) for i in (0,1)]
assert r[1][0] < r[0][0],r
assert r[1][1]*10 < r[0][1],r
print(f'PASS: z486 upper-RAM loop {r[0][0]} -> {r[1][0]} cycles; {r[0][1]} -> {r[1][1]} bus reads')
b=[int(re.search(r'bios_fetches=(\d+)',(p/f'run-1-{i}.log').read_text()).group(1)) for i in (0,1)]
assert b[0] > 0 and b[1] == 0, b
print(f'PASS: z486 BIOS call {b[0]} -> {b[1]} bus reads')
PY
