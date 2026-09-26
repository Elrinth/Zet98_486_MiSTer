#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SEGMENT_CASE_GENERATOR=tests/make_vipt_segment_overlap.py \
SEGMENT_EVIDENCE=/project/segment-overlap-evidence \
bash tests/run-z486-segment-admission.sh
