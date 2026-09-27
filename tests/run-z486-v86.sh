#!/usr/bin/env bash
# Virtual-8086 monitor test on the actual z486 CPU (EMM386/VEM486-style):
# paging + EMS-style remap, TSS I/O bitmap, #GP/#PF monitor, IOPL 0/3,
# INT reflection through the V86 IVT. tests/hardware/v86_monitor.asm.
# V86_DEFINES=-DV86_TRACE prints the page-walk trace on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/v86_monitor.asm -o "$out/v86.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG ${V86_DEFINES:-} \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 \
  -GTRACE_LIMIT=${TRACE_LIMIT:-0} -GWATCHDOG_NS=20000000 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/v86.bin") > "$out/run.log" 2>&1; then
  grep -v -e '^XMS EIP' -e '^V86TRACE' "$out/run.log" | tail -n 20
  if [ -n "${V86_DEFINES:-}" ]; then grep '^V86TRACE' "$out/run.log" | tail -n "${TRACE_TAIL:-40}"; fi
  exit 1
fi
echo 'PASS: z486 V86 monitor: paging/EMS remap, supervisor-only monitor pages, TSS I/O bitmap, #GP at IOPL 0 (CLI/PUSHF/POPF/INT/HLT), native CLI/STI at IOPL 3, #PF demand map, INT reflection via V86 IVT'
# Negative control: without the IOPL raise the reflected INT must fail.
sed 's/        or      dword \[esp + 24\], 3000h         ; IOPL 3 from now on/        nop/' \
  tests/hardware/v86_monitor.asm > "$out/negative.asm"
nasm -f bin "$out/negative.asm" -o "$out/negative.bin"
if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/negative.bin") > "$out/negative.log" 2>&1; then
  echo 'FAIL: V86 negative control passed'; exit 1
fi
grep -q 'protected-mode extended memory program failed' "$out/negative.log"
echo 'PASS: V86 negative control (no IOPL 3) rejected'
# Timer IRQs taken from V86 during a store loop (testbench PIT mode).
nasm -f bin -DIRQ_TEST tests/hardware/v86_monitor.asm -o "$out/v86irq.bin"
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD   -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG ${V86_DEFINES:-}   -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/objirq"   --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 -GPIT_PM_TEST=1   -GTRACE_LIMIT=${TRACE_LIMIT:-0} -GWATCHDOG_NS=40000000 "${sources[@]}"   rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv   rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv   rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compileirq.log" 2>&1 || { tail -n 60 "$out/compileirq.log"; exit 1; }
if ! (cd "$out"; "$out/objirq/Vz486_xms_resident_tb" "+program=$out/v86irq.bin") > "$out/irq.log" 2>&1; then
  grep -v -e '^XMS EIP' -e '^V86TRACE' "$out/irq.log" | tail -n 20
  exit 1
fi
grep '^PASS: protected32 IRQ' "$out/irq.log"
echo 'PASS: z486 V86 timer IRQs during a store loop: frames, EOI, IRETD back to V86, no lost or misplaced stores'
# Page directory and table in extended memory, written through the data cache
# from protected mode right before paging is enabled (EMM386 keeps them in XMS).
nasm -f bin -DEXT_PT tests/hardware/v86_monitor.asm -o "$out/v86ext.bin"
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/v86ext.bin") > "$out/ext.log" 2>&1; then
  grep -v -e '^XMS EIP' -e '^V86TRACE' "$out/ext.log" | tail -n 20
  exit 1
fi
echo 'PASS: z486 V86 monitor with page tables in extended memory written just before paging'
# EMM386's exact switch: GDT/tables copied to XMS, CR3/GDTR loaded in real
# mode, PE+PG in one MOV CR0, far JMP to selector 0B8h via the paged GDT.
nasm -f bin -DEMM_SEQ tests/hardware/v86_monitor.asm -o "$out/v86emm.bin"
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/v86emm.bin") > "$out/emm.log" 2>&1; then
  grep -v -e '^XMS EIP' -e '^V86TRACE' "$out/emm.log" | tail -n 20
  exit 1
fi
echo 'PASS: z486 EMM386-style real-mode PE+PG switch through a GDT in paged extended memory'
# HIMEM-style: tables and GDT written from unreal mode (real mode, 4 GB limits).
nasm -f bin -DEMM_SEQ -DUNREAL tests/hardware/v86_monitor.asm -o "$out/v86unreal.bin"
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/v86unreal.bin") > "$out/unreal.log" 2>&1; then
  grep -v -e '^XMS EIP' -e '^V86TRACE' "$out/unreal.log" | tail -n 20
  exit 1
fi
echo 'PASS: z486 EMM386 switch with page tables and GDT written from unreal mode (HIMEM style)'
