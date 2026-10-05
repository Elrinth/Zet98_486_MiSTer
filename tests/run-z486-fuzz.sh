#!/usr/bin/env bash
# Differential integer fuzzing of the actual z486 through the PC98 bridges.
# Each seed's RAM dump (40000h-9FFFFh) goes to $FUZZ_OUT for comparison with
# tests/z486_fuzz_compare.py (Unicorn). SEEDS, BLOCKS, BLOCK_LEN select runs.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${FUZZ_OUT:-/project/fuzz-out}
mkdir -p "$out"
out=$(cd "$out"; pwd)
profile_flags=()
for cache in ICACHE DCACHE; do
    option="Z486_${cache}_SET_BITS"
    value=${!option:-7}
    [[ $value == 7 || $value == 8 || ( $cache == ICACHE && $value == 9 ) ]] || {
        echo "$option: supported set bits are 7/8 (also 9 for ICACHE)" >&2; exit 2;
    }
    profile_flags+=("-DZET98_Z486_${cache}_SET_BITS=$value")
done
pipeline=${Z486_PIPELINE_REGS:-7}
[[ $pipeline =~ ^[0-7]$ ]] || { echo 'Z486_PIPELINE_REGS must be 0..7' >&2; exit 2; }
profile_flags+=("-DZET98_Z486_PIPELINE_REGS=$pipeline")
memory_grant=${Z486_MEMORY_GRANT:-1}
random_wait=${Z486_RANDOM_WAIT:-0}
registered_ready=${Z486_REGISTERED_MEMORY_READY:-1}
[[ $registered_ready == 0 || $registered_ready == 1 ]] || {
    echo 'Z486_REGISTERED_MEMORY_READY must be 0 or 1' >&2; exit 2;
}
[[ $memory_grant == 0 || $memory_grant == 1 ]] || {
    echo 'Z486_MEMORY_GRANT must be 0 or 1' >&2; exit 2;
}
[[ $random_wait =~ ^[0-9]+$ && $random_wait -le 100 ]] || {
    echo 'Z486_RANDOM_WAIT must be 0..100 clocks' >&2; exit 2;
}
profile_flags+=("-GEARLY_MEMORY_GRANT=$memory_grant" "-GRANDOM_WAIT=$random_wait"
               "-GREGISTERED_MEMORY_READY=$registered_ready")
native_fb=${Z486_NATIVE_DDR_FB_ONLY:-0}
[[ $native_fb == 0 || $native_fb == 1 ]] || {
    echo 'Z486_NATIVE_DDR_FB_ONLY must be 0 or 1' >&2; exit 2;
}
if [[ $native_fb == 1 ]]; then
    profile_flags+=(-DZET98_NATIVE_DDR -DZET98_NATIVE_DDR_FB_ONLY)
fi
printf '%s\n' "${profile_flags[@]}" "Z486_FUZZ_486=${Z486_FUZZ_486:-0}" \
    "SEEDS=${SEEDS:-1 2 3 4}" "BLOCKS=${BLOCKS:-1200}" \
    "BLOCK_LEN=${BLOCK_LEN:-12}" > "$out/profile.txt"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
  "${profile_flags[@]}" \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$work/obj" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 \
  -GTRACE_LIMIT=0 -GWATCHDOG_NS=400000000 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$work/compile.log" 2>&1 || { tail -n 60 "$work/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$work/"
for seed in ${SEEDS:-1 2 3 4}; do
    python3 tests/z486_fuzz_gen.py "$seed" "${BLOCKS:-1200}" "${BLOCK_LEN:-12}" "$out/fuzz-$seed.asm" "$out/fuzz-$seed.json"
    nasm -f bin "$out/fuzz-$seed.asm" -o "$out/fuzz-$seed.bin"
    if (cd "$work"; ./obj/Vz486_xms_resident_tb "+program=$out/fuzz-$seed.bin" "+dump=$out/fuzz-$seed.z486") > "$out/fuzz-$seed.log" 2>&1; then
        echo "RAN seed $seed"
    else
        echo "CPU FAILED seed $seed"; tail -n 5 "$out/fuzz-$seed.log"; exit 1
    fi
done
