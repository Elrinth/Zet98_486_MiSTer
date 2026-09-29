#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
evidence=/project/limit-isolation-evidence
mkdir "$evidence"
python3 tests/make_pm_payload_cpu.py "$out/probe.asm" --limit-short
cp "$out/probe.asm" "$evidence/"
nasm -DPM_LIMIT_CONTROL=1 -f bin "$out/probe.asm" -o "$out/warm.bin"
nasm -DPM_LIMIT_CONTROL=1 -DPM_LIMIT_COLD=1 -f bin "$out/probe.asm" -o "$out/cold.bin"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
compile() {
 verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$1" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 -GPM_PAYLOAD_TEST=1 -GPM_MIN_DDR=1 \
  -GTRACE_LIMIT=0 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$evidence/compile-$1.log" 2>&1 || { tail -n 40 "$evidence/compile-$1.log"; exit 1; }
}
trial() {
 local model=$1 kind=$2 expected=$3 label=$4; shift 4
 set +e
 (cd "$out"; "$out/obj-$model/Vz486_xms_resident_tb" "+program=$out/$kind.bin" "$@") > "$evidence/$label.log" 2>&1
 local result=$?
 set -e
 echo "RESULT $label exit=$result expected=$expected"
 tail -n 9 "$evidence/$label.log"
 if [ "$expected" = pass ]; then test "$result" -eq 0
 else test "$result" -ne 0; grep -q 'PM FAIL stage=101' "$evidence/$label.log"; fi
}
compile baseline
trial baseline warm fail baseline-warm
trial baseline cold fail baseline-cold
trial baseline warm pass all-hardwired-off-warm +z486_hardwired_off
trial baseline cold pass all-hardwired-off-cold +z486_hardwired_off
# Test-copy-only causal control: disable direct register/memory load candidates,
# retaining other hardwired instructions and all production checks. No RTL edit.
python3 - "$evidence/z486-direct-load-off.sv" <<'PY'
from pathlib import Path
import sys,hashlib
p=Path('rtl/vendor/z486/z486.sv');s=p.read_text()
a='assign d2_vipt_candidate = !hardwired_off &&'
assert s.count(a)==1
Path(sys.argv[1]).write_text(s.replace(a,'assign d2_vipt_candidate = 1\'b0 && !hardwired_off &&'))
print('BASELINE_CPU_SHA256',hashlib.sha256(p.read_bytes()).hexdigest())
PY
for i in "${!sources[@]}"; do
 if [ "${sources[$i]}" = rtl/vendor/z486/z486.sv ]; then sources[$i]="$evidence/z486-direct-load-off.sv"; fi
done
compile direct-off
trial direct-off warm pass direct-load-off-warm
trial direct-off cold pass direct-load-off-cold
echo 'PASS: direct-load segment-limit bypass isolated; baseline failure retained, no production fix or Doom causation claim'
