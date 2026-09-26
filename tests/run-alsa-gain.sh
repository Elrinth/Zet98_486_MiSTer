#!/usr/bin/env bash
# MIDI volume (Linux/ALSA audio gain in sys_top): extract the real function
# and check every setting, including saturation of the boost settings.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
{
  echo 'module alsa_gain_tb;'
  sed -n '/^function automatic \[15:0\] alsa_scale/,/^endfunction/p' MiSTer/sys/sys_top.v | tr -d '\r'
  cat <<'TB'
  integer g, v, want, got, errors = 0, checks = 0;
  integer num [0:7];
  initial begin
    num[0]=8; num[1]=6; num[2]=4; num[3]=2; num[4]=0; num[5]=10; num[6]=12; num[7]=16;
    for (g = 0; g < 8; g = g + 1)
      for (v = -32768; v < 32768; v = v + 97) begin
        want = (v * num[g]) >>> 3;
        if (want > 32767) want = 32767;
        if (want < -32768) want = -32768;
        got = $signed(alsa_scale(v[15:0], g[2:0]));
        checks = checks + 1;
        if (got != want) begin errors = errors + 1;
          if (errors < 5) $display("gain %0d in %0d: got %0d want %0d", g, v, got, want); end
      end
    if (errors) $fatal(1, "FAIL: %0d ALSA gain mismatches", errors);
    $display("PASS: MIDI volume gain, 8 settings, %0d samples incl. saturation", checks);
  end
endmodule
TB
} > "$out/tb.sv"
iverilog -g2012 -o "$out/tb" "$out/tb.sv"
vvp "$out/tb"
