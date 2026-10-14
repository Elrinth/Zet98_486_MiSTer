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
# Both drives mounted together, reads interleaved through the shared checker.
iverilog -g2012 -s native_image_dual_tb -o "$out/dual" rtl/storage/pc98_floppy_images.sv tests/native_image_dual_tb.sv
for pair in "d88 d88-80-18" "d88-40-8 d88-80-15" "d88-80-9 d88"; do
  set -- $pair
  vvp "$out/dual" "+image0=$out/$1.image" "+expected0=$out/$1.expected" "+image1=$out/$2.image" "+expected1=$out/$2.expected"
done
# Negative control: a checker that accepts any header must fail the HDM case.
sed 's/disk_size == size \&\& media_type <= 8.h20/1/' rtl/storage/pc98_floppy_images.sv > "$out/lax.sv"
! cmp -s rtl/storage/pc98_floppy_images.sv "$out/lax.sv"
iverilog -g2012 -s native_image_tb -Pnative_image_tb.FLOPPY=1 -Pnative_image_tb.SLOT=0 -o "$out/lax" "$out/lax.sv" rtl/storage/pc98_hdi_image.sv tests/native_image_tb.sv
if vvp "$out/lax" "+image=$out/hdm-77-8.image" "+expected=$out/hdm-77-8.expected" +reject=1 +direct=0 > "$out/lax.log" 2>&1; then
  echo "FAIL: non-D88 header accepted"; exit 1
fi
grep -q "invalid format accepted" "$out/lax.log" || { cat "$out/lax.log"; exit 1; }
echo "PASS: non-D88 header rejection is enforced"
