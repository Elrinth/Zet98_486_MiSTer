#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 100 MHz system clock against the unchanged 100 MHz memory / 75 MHz video.
# Each transfer test retains its routing-delay and deliberately broken controls.
export CPU_RATES=100
for test in sdram-write-bundle sub-write-bundle sdram-read-bundle \
            floppy-sdram floppy-read-bundle sdram-control-cdc \
            video-sdram video-settings video-status video-calc; do
    bash "tests/run-$test.sh"
done
