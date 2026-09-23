#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for delay in 15 80; do
    sed -e "s/fde_request_crossing <= fde_request_source; -- FDE_REQUEST_BUNDLE_TRANSPORT/fde_request_crossing <= transport fde_request_source after $delay ns;/" \
        -e "s/fec_request_crossing <= fec_request_source; -- FEC_REQUEST_BUNDLE_TRANSPORT/fec_request_crossing <= transport fec_request_source after $delay ns;/" \
        -e "/FDE_REQUEST_BUNDLE_ADMISSION/a\\                    assert fde_request_crossing'stable(5 ns) report \"floppy request bundle arrived too late\" severity failure;" \
        -e "/FEC_REQUEST_BUNDLE_ADMISSION/a\\                    assert fec_request_crossing'stable(5 ns) report \"floppy request bundle arrived too late\" severity failure;" \
        Zet98/sdramc.vhd > "$out/sdram-$delay.vhd"
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-15.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for port in false true; do
    for mhz in ${CPU_RATES:-20 40 50 60 90 100}; do
        for phase in 0 1300 4700 9100; do
            ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb \
                -gUSE_FEC="$port" -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" --assert-level=error
            ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb \
                -gUSE_FEC="$port" -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" -gCONTINUOUS=true --assert-level=error
        done
    done
    for mhz in 20 40 50 60; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb \
            -gUSE_FEC="$port" -gCPU_MHZ="$mhz" -gBUFFERED=false --assert-level=error
    done
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/sdram-80.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for port in false true; do
    if ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb -gUSE_FEC="$port" \
        -gCPU_MHZ=60 --assert-level=error > "$out/late-write.log" 2>&1; then
        echo 'FAIL: late floppy request accepted'; exit 1
    fi
    grep -Eq 'floppy request bundle arrived too late|floppy SDRAM (row/bank|write data) mismatch' "$out/late-write.log"
    echo "PASS: late floppy request rejected, FEC=$port"
done
sed -e "s/if FDEbusy='1' and FDEdone_sync(1)=FDEREQ then -- FDE_READ_COMPLETION_CAPTURE/if FDEACKb='1' then -- late read/" \
    -e "s/if FECbusy='1' and FECdone_sync(1)=FECREQ then -- FEC_READ_COMPLETION_CAPTURE/if FECACKb='1' then -- late read/" \
    Zet98/sdramc.vhd > "$out/late-read.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/late-read.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for port in false true; do
    if ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb -gUSE_FEC="$port" \
        -gCPU_MHZ=60 --assert-level=error > "$out/late-read.log" 2>&1; then
        echo 'FAIL: late floppy read accepted'; exit 1
    fi
    grep -q 'floppy read data missing on WAIT completion' "$out/late-read.log"
    echo "PASS: late floppy read rejected, FEC=$port"
done

# Reusing an old high completion level must not acknowledge a new request.
sed -e "s/fdeend<=lFDEREQ(2);/fdeend<='1';/" \
    -e "s/fecend<=lFECREQ(2);/fecend<='1';/" Zet98/sdramc.vhd > "$out/stale-completion.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/stale-completion.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for port in false true; do
    if ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb -gUSE_FEC="$port" \
        -gCPU_MHZ=60 -gCONTINUOUS=true --assert-level=error > "$out/stale-completion.log" 2>&1; then
        echo 'FAIL: stale floppy completion accepted'; exit 1
    fi
    grep -q 'floppy request timed out' "$out/stale-completion.log"
    echo "PASS: stale floppy completion rejected, FEC=$port"
done
