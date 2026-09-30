#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/native_image_fixtures.py "$out"
iverilog -g2012 -s native_image_tb -Pnative_image_tb.FLOPPY=0 -o "$out/hdi"   rtl/storage/pc98_floppy_images.sv rtl/storage/pc98_hdi_image.sv tests/native_image_tb.sv
for slot in 0 1; do
  iverilog -g2012 -s native_image_tb -Pnative_image_tb.FLOPPY=1 -Pnative_image_tb.SLOT=$slot -o "$out/floppy$slot"     rtl/storage/pc98_floppy_images.sv rtl/storage/pc98_hdi_image.sv tests/native_image_tb.sv
done
while read -r name reject direct; do
  case "$name" in
    hdi*|raw) case "$name" in hdi) info=20411;; hdi-256) info=30422;; *) info=0;; esac
      vvp "$out/hdi" "+image=$out/$name.image" "+expected=$out/$name.expected" +reject=$reject +direct=$direct +info=$info ;;
    *) for slot in 0 1; do
         vvp "$out/floppy$slot" "+image=$out/$name.image" "+expected=$out/$name.expected" +reject=$reject +direct=$direct
       done ;;
  esac
done < "$out/cases.txt"
# Both drives mounted together, reads interleaved through the one converter.
iverilog -g2012 -s native_image_dual_tb -o "$out/dual" rtl/storage/pc98_floppy_images.sv tests/native_image_dual_tb.sv
for pair in "hdm-77-8 fdi-37" "fdi-4096 d88" "d88 hdm-80-18" "hdm-40-8 hdm-80-15"; do
  set -- $pair
  vvp "$out/dual" "+image0=$out/$1.image" "+expected0=$out/$1.expected" "+image1=$out/$2.image" "+expected1=$out/$2.expected"
done
# Negative control: a converter that keeps the previous drive's geometry
# (no per-drive reload) must fail the dual test.
sed 's/base<=slot_base\[owner\]; virtual_size<=slot_virtual\[owner\];/virtual_size<=slot_virtual[owner];/' \
  rtl/storage/pc98_floppy_images.sv > "$out/stale.sv"
! cmp -s rtl/storage/pc98_floppy_images.sv "$out/stale.sv"
iverilog -g2012 -s native_image_dual_tb -o "$out/stale" "$out/stale.sv" tests/native_image_dual_tb.sv
if vvp "$out/stale" "+image0=$out/hdm-77-8.image" "+expected0=$out/hdm-77-8.expected" \
     "+image1=$out/fdi-4096.image" "+expected1=$out/fdi-4096.expected" > "$out/stale.log" 2>&1; then
  echo "FAIL: stale per-drive geometry accepted"; exit 1
fi
grep -q "drive [01] LBA" "$out/stale.log" || { cat "$out/stale.log"; exit 1; }
echo "PASS: stale per-drive geometry rejected"
