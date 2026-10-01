#!/usr/bin/env bash
# z486 CPU speed (execution-rate throttle) on the actual CPU through the PC-98
# bridges, at every OSD setting (0 Full, 1 33 MHz, 2 8 MHz, 3 3 MHz):
#  - mixed integer/memory/stack/REP probe: identical result, RAM dump and
#    instruction count at every speed; wall-clock rate matches the target;
#  - PCMDRV-style INT dispatcher (hung at every slow setting while the
#    throttle held a resident D2 successor);
#  - a generated integer fuzz program (tests/z486_fuzz_gen.py): identical
#    instruction count and RAM dump at every speed (a held D2 successor once
#    lost a microcoded load's EAX write here);
#  - long REP STOS/MOVS/CMPS/SCAS/LODS forms with restarts, with and without
#    timer IRQs; no timer interrupt may be lost while REP debt is repaid;
#  - negative controls: the rate checker rejects an unthrottled run, holding
#    the resident D2 successor (the old scheme) hangs the dispatcher, and
#    without the REP restart exit timer interrupts are lost at 3 MHz.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
build() { # build <dir> <source root> [verilator -G args]
    local dir=$1 src=$2; shift 2
    (cd "$src" && verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
      -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
      -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/$dir" \
      --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 \
      -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 "$@" "${sources[@]}" \
      rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
      rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
      rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv) > "$out/$dir.log" 2>&1 || {
        tail -n 60 "$out/$dir.log"; exit 1; }
}
for p in cpu_speed_probe cpu_speed_rep_probe cpu_speed_irq_probe cs_indirect_call; do
    nasm -f bin "tests/hardware/$p.asm" -o "$out/$p.bin"
done
python3 tests/z486_fuzz_gen.py 11 400 12 "$out/fuzz.asm" "$out/fuzz.json" > /dev/null
nasm -f bin "$out/fuzz.asm" -o "$out/fuzz.bin"
build plain "$root"
build pit "$root" -GPIT_PM_TEST=1
cp rtl/vendor/z486/*.hex "$out/"
cd "$out"
run() { # run <obj> <program> <speed> [args] -> log, fails on any error
    local log="$out/$2-$1-$3.log"
    if ! "./$1/Vz486_xms_resident_tb" "+program=$out/$2.bin" "+cpu_speed=$3" "${@:4}" > "$log" 2>&1 ||
       ! grep -q '^PASS: actual z486' "$log"; then
        grep -v '^XMS EIP' "$log" | tail -n 15; echo "FAIL: $2 at speed $3 ($1)"; exit 1
    fi
}
field() { grep '^RATE' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p"; }
mhz=(90 33 8 3)
# Rate check: wall cycles must equal charged execution cycles scaled by
# 90/target within 3% (exactly 1 at Full), and the program must be no
# faster than at Full.
check_rate() { # check_rate <log> <speed> <full cycles>
    local c a
    c=$(field "$1" cycles); a=$(field "$1" active)
    awk -v c="$c" -v a="$a" -v t="${mhz[$2]}" -v f="$3" -v s="$2" 'BEGIN {
        e = s == 0 ? c : a * 90 / t; r = c / e
        printf "speed %d: %d cycles, %d charged, %.3fx of 90/%d, %.2fx Full time\n", s, c, a, r, t, c / f
        exit !(r > 0.97 && r < 1.03 && (s == 0 || c > f * 1.5)) }'
}
for sp in 0 1 2 3; do
    run plain cpu_speed_probe "$sp" "+dump=$out/probe-$sp.dump"
    run plain cpu_speed_rep_probe "$sp" "+dump=$out/rep-$sp.dump"
    run pit cpu_speed_rep_probe "$sp" "+dump=$out/rep-irq-$sp.dump"
    run pit cpu_speed_irq_probe "$sp"
    run plain cs_indirect_call "$sp"
    run plain fuzz "$sp" "+dump=$out/fuzz-$sp.dump"
done
full=$(field "$out/cpu_speed_probe-plain-0.log" cycles)
insns=$(field "$out/cpu_speed_probe-plain-0.log" issued)
for sp in 0 1 2 3; do
    log="$out/cpu_speed_probe-plain-$sp.log"
    check_rate "$log" "$sp" "$full" || { echo "FAIL: speed $sp execution rate"; exit 1; }
    [ "$(field "$log" issued)" = "$insns" ] || { echo "FAIL: speed $sp instruction count"; exit 1; }
    cmp -s probe-0.dump "probe-$sp.dump" || { echo "FAIL: speed $sp probe RAM differs"; exit 1; }
    cmp -s rep-0.dump "rep-$sp.dump" || { echo "FAIL: speed $sp REP RAM differs"; exit 1; }
    cmp -s rep-0.dump "rep-irq-$sp.dump" || { echo "FAIL: speed $sp REP+IRQ RAM differs"; exit 1; }
    cmp -s fuzz-0.dump "fuzz-$sp.dump" || { echo "FAIL: speed $sp fuzz RAM differs"; exit 1; }
    [ "$(field "$out/fuzz-plain-$sp.log" issued)" = "$(field "$out/fuzz-plain-0.log" issued)" ] ||
        { echo "FAIL: speed $sp fuzz instruction count"; exit 1; }
    awk -v i="$(field "$log" issued)" -v c="$(field "$log" cycles)" -v s="$sp" \
        'BEGIN { printf "speed %d: %.2f MIPS on the probe mix\n", s, i / c * 90 }'
done
# Every timer tick while IRQ0 is unmasked must be serviced (one may straddle
# the mask edges).
irq_check() { # irq_check <log>
    local a w
    a=$(sed -n 's/.*accepted=\([0-9]*\).*window=\([0-9]*\).*/\1/p' "$1")
    w=$(sed -n 's/.*window=\([0-9]*\).*/\1/p' "$1")
    awk -v a="$a" -v w="$w" 'BEGIN { e = w / 10000; printf "%d of %.1f timer IRQs\n", a, e; exit !(a >= e - 1.5) }'
}
for sp in 0 1 2 3; do
    echo -n "speed $sp IRQ during long REP: "
    irq_check "$out/cpu_speed_irq_probe-pit-$sp.log" || { echo "FAIL: speed $sp lost timer IRQs"; exit 1; }
    echo -n "speed $sp IRQ during REP forms: "
    irq_check "$out/cpu_speed_rep_probe-pit-$sp.log" || { echo "FAIL: speed $sp lost timer IRQs"; exit 1; }
done
echo 'PASS: z486 CPU speed Full/33/8/3: identical results, exact rates, REP restarts, prompt IRQs, dispatcher, fuzz'

# Negative control 1: the rate checker rejects the Full run presented as 3 MHz.
if check_rate "$out/cpu_speed_probe-plain-0.log" 3 "$full" > /dev/null; then
    echo "FAIL: rate check accepted an unthrottled run"; exit 1
fi
# Negative controls 2 and 3 rebuild a disposable copy of the CPU.
neg="$out/neg"
mkdir -p "$neg/tests"
cp -r "$root/rtl" "$neg/"
cp "$root/tests/z486_xms_resident_tb.sv" "$neg/tests/"
z="$neg/rtl/vendor/z486/z486.sv"
# Old scheme: launch freely, hold the resident successor at D2->EX instead.
sed -i -e 's/!fault_suppress_delay_slot \&\& !interrupt_entry \&\&$/!fault_suppress_delay_slot \&\& !interrupt_entry;/' \
       -e '/^                         !throttle_hold;$/d' \
       -e 's/^wire       d2_ready_before_fault = d2_payload_ready \&\& !stall \&\&$/& !throttle_hold \&\&/' "$z"
grep -q 'd2_payload_ready && !stall && !throttle_hold &&' "$z" && ! grep -q '^                         !throttle_hold;$' "$z" ||
    { echo "FAIL: negative hold edit"; exit 1; }
build negpark "$neg"
if (./negpark/Vz486_xms_resident_tb "+program=$out/cs_indirect_call.bin" +cpu_speed=1 \
       > "$out/negpark.log" 2>&1) 2> /dev/null; then
    echo "FAIL: dispatcher completed while holding the resident D2 successor"; exit 1
fi
grep -q 'XMS watchdog' "$out/negpark.log" || { tail -n 5 "$out/negpark.log"; echo "FAIL: unexpected negative hold failure"; exit 1; }
echo 'PASS: negative control: holding the resident D2 successor hangs the dispatcher at 33 MHz'
cp "$root/rtl/vendor/z486/z486.sv" "$z"
sed -i 's/no_interrupt = !interrupt_pending \&\& !throttle_rep_break_r;/no_interrupt = !interrupt_pending;/' "$z"
grep -q 'no_interrupt = !interrupt_pending;' "$z" || { echo "FAIL: negative REP edit"; exit 1; }
build negrep "$neg" -GPIT_PM_TEST=1
./negrep/Vz486_xms_resident_tb "+program=$out/cpu_speed_irq_probe.bin" +cpu_speed=3 > "$out/negrep.log" 2>&1 || {
    tail -n 5 "$out/negrep.log"; echo "FAIL: negative REP run did not complete"; exit 1; }
if irq_check "$out/negrep.log" > /dev/null; then
    echo "FAIL: no timer IRQs lost without the REP restart exit"; exit 1
fi
echo "PASS: negative control: without the REP restart exit, 3 MHz serviced only $(irq_check "$out/negrep.log" || true)"
