#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/video_settings_mapping.py
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 --workdir="$out" rtl/reset_release.vhd rtl/video_settings_transfer.vhd tests/video_settings_transfer_tb.vhd
ghdl -e --std=08 --workdir="$out" video_settings_transfer_tb
ghdl -r --std=08 --workdir="$out" video_settings_transfer_tb --assert-level=error
python3 - "$out/delayed.vhd" <<'PY'
from pathlib import Path
import sys
source=Path('rtl/video_settings_transfer.vhd').read_text()
replacements={
    'signal request_sync,ack_sync:std_logic_vector(1 downto 0);':
    '''signal request_sync,ack_sync:std_logic_vector(1 downto 0);
    signal test_capture_time:time:=0 ns;
    signal test_captured:boolean:=false;''',
    'held_data<=settings_in;':
    '''assert not test_captured or now-test_capture_time>=20 ns
                    report "settings source changed before acknowledgement round trip" severity failure;
                held_data<=settings_in;''',
    "received_data<=(others=>'0');ack_toggle<='0';request_sync<=\"00\";":
    "received_data<=(others=>'0');ack_toggle<='0';request_sync<=\"00\";test_captured<=false;",
    'received_data<=transfer_data;':
    'test_capture_time<=now;test_captured<=true;received_data<=transfer_data;',
    'transfer_data<=held_data;':
    'transfer_data<=transport held_data after 20 ns;'
}
for old,new in replacements.items():
    assert source.count(old)==1,old
    source=source.replace(old,new)
Path(sys.argv[1]).write_text(source)
PY
ghdl -a --std=08 --workdir="$out" "$out/delayed.vhd" tests/video_settings_transfer_tb.vhd
ghdl -e --std=08 --workdir="$out" video_settings_transfer_tb
for mhz in 20 40 50 60 90 100; do
    for phase in 1300 4700 9100; do
        ghdl -r --std=08 --workdir="$out" video_settings_transfer_tb -gCPU_MHZ="$mhz" -gVIDEO_PHASE_PS="$phase" --assert-level=error
    done
done
for fault in late early live ack_early; do
    case "$fault" in
        late) sed 's/after 20 ns/after 60 ns/' "$out/delayed.vhd" > "$out/bad.vhd";;
        early) sed 's/request_sync(1)/request_sync(0)/g' "$out/delayed.vhd" > "$out/bad.vhd";;
        live) sed 's/transport held_data after 20 ns/settings_in/' "$out/delayed.vhd" > "$out/bad.vhd";;
        ack_early) sed 's/if ack_sync(1)=request_toggle/if ack_sync(0)=request_toggle/' "$out/delayed.vhd" > "$out/bad.vhd";;
    esac
    ghdl -a --std=08 --workdir="$out" "$out/bad.vhd" tests/video_settings_transfer_tb.vhd
    ghdl -e --std=08 --workdir="$out" video_settings_transfer_tb
    if ghdl -r --std=08 --workdir="$out" video_settings_transfer_tb --assert-level=error > "$out/bad.log" 2>&1; then
        echo "FAIL: $fault settings negative control passed";exit 1
    fi
    grep -Eq 'settings payload not settled|settings source changed before acknowledgement round trip' "$out/bad.log" || { cat "$out/bad.log";exit 1; }
    echo "PASS: $fault settings negative control rejected"
done
