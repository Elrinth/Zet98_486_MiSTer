#!/usr/bin/env bash
# D88 -> diskemu_mister (MiSTer sd model, SDRAM track cache) -> FDemu -> FDC,
# with BIOS-like SPECIFY/RECALIBRATE/SEEK/READ ID/READ DATA over DMA.
#   std : 2HD MFM sanity (+ the boot's FM READ ID probe must fail in time)
#   fm  : Xanadu-style FM 26x128 track 0/1, IPL whole-track read, 360 rpm,
#         every track word in the D88 density (gap 4a was the other one),
#         then Xanadu's own driver reads with port 94h bit 3 (motor) clear
#   loh : Legend of Heroes-style R=1,49..55 read with the BIOS EOT of 8
# Optional private images (not in the repo), full load then per-cylinder scan:
#   FDC_D88_IMAGES="/path/xan1.d88 /path/loh1.d88" tests/run-fdc-d88.sh
# FDC_D88_RATES (kHz, default 20000) selects SYSFREQ; 90000 is ~5x slower.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/fdc_d88_fixtures.py "$out"

build() { # workdir FDC.vhd FDemu.vhd diskemu_mister.vhd
    local w=$1
    mkdir -p "$w"
    # GHDL 1.0 needs: an others arm in seekcont, no expressions in port maps.
    perl -0pe 's/(tdo\(3\)<=tdi\(3\);\s*)end case;/$1when others => null;\n\t\t\t\tend case;/' \
        FDC/seekcont.vhd > "$w/seekcont.vhd"
    python3 tests/ghdl_port_exprs.py "$2" "$w/FDC.vhd"
    python3 tests/ghdl_port_exprs.py "$3" "$w/FDemu.vhd"
    ghdl -a --std=08 -fsynopsys --workdir="$w" \
        LIB/CRCGENN.vhd LIB/sftgen.vhd LIB/sftdiv.vhd LIB/signext.vhd LIB/digifilter.vhd \
        FDC/FDC_timing.vhd FDC/FDC_sectinfo.vhd FDC/fmmod.vhd FDC/mfmmod.vhd FDC/fmdem.vhd \
        FDC/mfmdem.vhd FDC/headseek.vhd "$w/seekcont.vhd" FDC/nrdet.vhd "$w/FDC.vhd" \
        Zet98/FDtiming.vhd tests/fdc_d88_models.vhd diskemu_mister/FECcont.vhd \
        diskemu_mister/tracktable.vhd diskemu_mister/mkgapsync.vhd "$w/FDemu.vhd" \
        diskemu_mister/wrotecont.vhd diskemu_mister/sasidev.vhd diskemu_mister/sramcont.vhd \
        "$4" tests/fdc_d88_tb.vhd 2>/dev/null
    ghdl -e --std=08 -fsynopsys --workdir="$w" fdc_d88_tb 2>/dev/null
}
run() { # workdir test image [generics...]
    local w=$1 t=$2 i=$3; shift 3
    ghdl -r --std=08 -fsynopsys --workdir="$w" fdc_d88_tb -gTEST="$t" -gIMAGE="$i" "$@" \
        --ieee-asserts=disable 2>&1 | grep -v 'warning' | sed 's/^tests\/fdc_d88_tb.vhd:[0-9:]*//'
    return "${PIPESTATUS[0]}"
}
expect_fail() { # name pattern workdir test image [generics...]
    local name=$1 pattern=$2; shift 2
    if run "$@" --assert-level=error > "$out/neg.log" 2>&1; then
        cat "$out/neg.log"; echo "FAIL: $name accepted"; exit 1
    fi
    grep -q "$pattern" "$out/neg.log" || { cat "$out/neg.log"; echo "FAIL: $name: wrong failure"; exit 1; }
    echo "PASS: $name rejected"
}

build "$out/new" FDC/FDC.vhd diskemu_mister/FDemu.vhd diskemu_mister/diskemu_mister.vhd
for rate in ${FDC_D88_RATES:-20000}; do
    for t in std fm loh; do
        run "$out/new" "$t" "$out/$t.d88" -gSYSFREQ="$rate" --assert-level=error
    done
done
for image in ${FDC_D88_IMAGES:-}; do
    run "$out/new" scan "$image" -gLOAD_MS=20000 -gLIMIT_MS=2000 --assert-level=error
done

# Negative controls: each fix reverted on its own must fail.
sed -e 's/if(R\/=EOT)then/if(R<EOT)then/' -e 's/elsif(R=EOT/elsif(R>=EOT/' FDC/FDC.vhd > "$out/FDC-eot.vhd"
! cmp -s FDC/FDC.vhd "$out/FDC-eot.vhd"
build "$out/eot" "$out/FDC-eot.vhd" diskemu_mister/FDemu.vhd diskemu_mister/diskemu_mister.vhd
expect_fail "track end on R>=EOT" "READ DATA status error\|transferred" "$out/eot" loh "$out/loh.d88"

sed 's/if(nturns<1)then/if(nturns<3)then/' FDC/FDC.vhd > "$out/FDC-4idx.vhd"
! cmp -s FDC/FDC.vhd "$out/FDC-4idx.vhd"
build "$out/4idx" "$out/FDC-4idx.vhd" diskemu_mister/FDemu.vhd diskemu_mister/diskemu_mister.vhd
expect_fail "missing AM after four index pulses" "BIOS gives up" "$out/4idx" std "$out/std.d88"

sed 's/step:=2;/step:=1;/' diskemu_mister/FDemu.vhd > "$out/FDemu-fm.vhd"
! cmp -s diskemu_mister/FDemu.vhd "$out/FDemu-fm.vhd"
build "$out/fmrev" FDC/FDC.vhd "$out/FDemu-fm.vhd" diskemu_mister/diskemu_mister.vhd
expect_fail "FM track at half speed" "revolution is" "$out/fmrev" fm "$out/fm.d88"

sed 's/if((trackno+1)<tracks)then/if(trackno<tracks)then/' diskemu_mister/diskemu_mister.vhd > "$out/diskemu-164.vhd"
! cmp -s diskemu_mister/diskemu_mister.vhd "$out/diskemu-164.vhd"
build "$out/t164" FDC/FDC.vhd diskemu_mister/FDemu.vhd "$out/diskemu-164.vhd"
expect_fail "track table entry 164" "not loaded after" "$out/t164" fm "$out/fm.d88"
perl -0pe 's/bytecount<=40;(\s*)trackwrdat<=x"00ff";(\s*)else(\s*)bytecount<=80;(\s*)trackwrdat<=x"024e";/bytecount<=80;$1trackwrdat<=x"024e";$2else$3bytecount<=40;$4trackwrdat<=x"00ff";/'     diskemu_mister/diskemu_mister.vhd > "$out/diskemu-gap.vhd"
! cmp -s diskemu_mister/diskemu_mister.vhd "$out/diskemu-gap.vhd"
build "$out/gap" FDC/FDC.vhd diskemu_mister/FDemu.vhd "$out/diskemu-gap.vhd"
expect_fail "gap 4a in the other density" "words of the wrong density" "$out/gap" fm "$out/fm.d88"
sed 's/motorn<=	"00" when fdc_ifmode=.1. else fdc_motorn;/motorn<=fdc_motorn;/'     diskemu_mister/diskemu_mister.vhd > "$out/diskemu-motor.vhd"
! cmp -s diskemu_mister/diskemu_mister.vhd "$out/diskemu-motor.vhd"
build "$out/motor" FDC/FDC.vhd diskemu_mister/FDemu.vhd "$out/diskemu-motor.vhd"
# Old logic: drive not ready, ST0=C8h after the 800 ms ready timeout.
expect_fail "port 94h motor bit stopping the 1MB drive" "BIOS gives up\|status error" "$out/motor" fm "$out/fm.d88"
echo "PASS: fdc-d88"
