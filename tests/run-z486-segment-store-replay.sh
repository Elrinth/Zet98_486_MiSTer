#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SEGMENT_CASE_GENERATOR=tests/make_vipt_segment_store_replay.py \
SEGMENT_CANDIDATE_GENERATOR=tests/make_vipt_segment_replay_trace.py \
SEGMENT_EVIDENCE=/project/segment-store-replay-evidence \
bash tests/run-z486-segment-admission.sh
