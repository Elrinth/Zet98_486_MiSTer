#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd VIDEO/GRAPHSCR98.vhd tests/graphics_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" graphics_address_tb
# GDC at 5 MHz: pitch counts each line twice (Windows 95 EGC driver, pitch 80)
for length in 3 400 0; do
    for repeat in 0 1; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gFAST=1 -gREPEATS="$repeat" -gFIRST_LENGTH="$length" --assert-level=error
    done
done
ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gFAST=1 -gREPEATS=1 \
    -gFIRST_LENGTH=40 -gSECOND_LENGTH=60 -gTHIRD_LENGTH=80 -gFOURTH_LENGTH=100 --assert-level=error
# Negative control: the full 5 MHz pitch as the line step must be rejected.
neg="$out/neg"; mkdir -p "$neg"
tr -d '\r' < VIDEO/GRAPHSCR98.vhd | sed "s/pitch_frame<='0' \& pitch_pixel(7 downto 1);/pitch_frame<=pitch_pixel;/" > "$neg/GRAPHSCR98.vhd"
! grep -q "pitch_pixel(7 downto 1)" "$neg/GRAPHSCR98.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$neg" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd "$neg/GRAPHSCR98.vhd" tests/graphics_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$neg" graphics_address_tb
if ghdl -r --std=08 -fsynopsys --workdir="$neg" graphics_address_tb -gFAST=1 --assert-level=error > "$neg/log" 2>&1; then
    echo 'FAIL: full 5 MHz pitch accepted as the line step'; exit 1
fi
grep -q 'Graphics address row=' "$neg/log" || { cat "$neg/log"; exit 1; }
echo 'PASS: full 5 MHz pitch rejected'
for length in 1 3 200 400 513 1023 0; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gFIRST_LENGTH="$length" --assert-level=error
done
for repeat in 1 3 31; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gREPEATS="$repeat" --assert-level=error
done
# LEN counts raster lines with doubled lines too (Flame Zapper: 2 x rows), odd splits included
for length in 2 7 398; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gREPEATS=1 -gFIRST_LENGTH="$length" --assert-level=error
done
# Four areas in order, then area 1 again (Steam Heart's cutscene), with repeats
for areas in "40 60 80 100" "16 32 48 64" "100 0 0 0" "0 5 5 5" "120 120 80 0" "7 9 11 13"; do
    set -- $areas
    for repeat in 0 1 2; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gREPEATS="$repeat"             -gFIRST_LENGTH="$1" -gSECOND_LENGTH="$2" -gTHIRD_LENGTH="$3" -gFOURTH_LENGTH="$4" --assert-level=error
    done
done
