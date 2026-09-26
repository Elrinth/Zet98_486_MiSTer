#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
timeout --kill-after=10s 120s python3 tests/prove_vipt_flat_admission.py
