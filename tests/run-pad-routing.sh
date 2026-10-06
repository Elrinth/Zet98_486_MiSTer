#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/pad_routing_check.py
# Exercise the existing key make/break path that consumes pad_keys.
bash tests/run-kbconv-padkeys.sh
