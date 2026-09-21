#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for variant in good bad; do
    sed '$d' tests/crtc_compositor_tb.vhd > "$out/$variant.vhd"
    sed -n '/GRPHB<=/,/gclk<=/p' VIDEO/CRTC98.vhd | sed '$d' > "$out/mux.vhd"
    if [[ $variant == bad ]]; then
        sed -i -e 's/graphen_video/GRAPHEN/g' -e 's/txten_video/TXTEN/g' "$out/mux.vhd"
    fi
    cat "$out/mux.vhd" >> "$out/$variant.vhd"
    printf 'end architecture;\n' >> "$out/$variant.vhd"
    ghdl -a --std=08 --workdir="$out" "$out/$variant.vhd"
    ghdl -e --std=08 --workdir="$out" crtc_compositor_tb
    if [[ $variant == good ]]; then
        ghdl -r --std=08 --workdir="$out" crtc_compositor_tb --assert-level=error
    else
        if ghdl -r --std=08 --workdir="$out" crtc_compositor_tb --assert-level=error > "$out/bad.log" 2>&1; then
            echo 'FAIL: compositor bypass negative control passed'; exit 1
        fi
        grep -q 'CPU enable bypassed video stage' "$out/bad.log"
        echo 'PASS: compositor bypass negative control rejected'
    fi
done
