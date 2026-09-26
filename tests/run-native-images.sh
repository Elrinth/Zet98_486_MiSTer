#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/native_image_fixtures.py "$out"
for floppy in 0 1; do
  iverilog -g2012 -s native_image_tb -Pnative_image_tb.FLOPPY=$floppy -o "$out/test$floppy" \
    rtl/storage/pc98_floppy_image.sv rtl/storage/pc98_hdi_image.sv tests/native_image_tb.sv
done
while read -r name reject direct; do
  floppy=1
  case "$name" in hdi*|raw) floppy=0;; esac
  vvp "$out/test$floppy" "+image=$out/$name.image" "+expected=$out/$name.expected" +reject=$reject +direct=$direct
done < "$out/cases.txt"
