#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s crash_recorder_freeze_tb -o "$out/tb" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_freeze_tb.sv
vvp -n "$out/tb"
iverilog -g2012 -s crash_recorder_freeze_tb -Pcrash_recorder_freeze_tb.FREEZE_IP="17'h1049d" -o "$out/ip" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_freeze_tb.sv
vvp -n "$out/ip"
iverilog -g2012 -s crash_recorder_freeze_tb -Pcrash_recorder_freeze_tb.FREEZE_CS=0 -Pcrash_recorder_freeze_tb.FREEZE_VECTOR="9'h106" -o "$out/vec" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_freeze_tb.sv
vvp -n "$out/vec"
# Negative control: without a watched CS nothing freezes, so no dump appears.
iverilog -g2012 -s crash_recorder_freeze_tb -Pcrash_recorder_freeze_tb.FREEZE_CS=0 -o "$out/off" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_freeze_tb.sv
if vvp -n "$out/off" > "$out/off.log" 2>&1; then echo 'FAIL: froze without DE_FREEZE_CS'; exit 1; fi
grep -q timeout "$out/off.log" || { cat "$out/off.log"; exit 1; }
echo 'PASS: no freeze without DE_FREEZE_CS'
iverilog -g2012 -s crash_recorder_quiet_tb -o "$out/quiet" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_quiet_tb.sv
vvp -n "$out/quiet"
iverilog -g2012 -s crash_recorder_itrace_tb -o "$out/itrace" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_itrace_tb.sv
vvp -n "$out/itrace"
iverilog -g2012 -s crash_recorder_itrace_tb -Pcrash_recorder_itrace_tb.WATCH=1 -o "$out/itw" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_itrace_tb.sv
vvp -n "$out/itw"
iverilog -g2012 -s crash_recorder_itrace_tb -Pcrash_recorder_itrace_tb.WATCH=1 -Pcrash_recorder_itrace_tb.WPOST=3 -o "$out/itwp" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_itrace_tb.sv
vvp -n "$out/itwp"
