# Segment-access timing

The 66 MHz isolated CPU fit after the decode-buffer change reports a
-1.221 ns path through read_segment's five-bit remaining-length mux,
comparison and memory completion logic. The length comparison now runs
for each segment before selecting a one-bit result. No pipeline stage,
CPU cycle, exception condition or address calculation is changed.

The unchanged reference checks all seven outputs in 4,637,520 cases:
random descriptors and controls plus every read length and segment
selector around limit boundaries, with code/data/expand-down, G and DB
flags. Invalid selectors retain the original GS fallback semantics.
A deliberately off-by-one limit comparison is rejected.

The full CPU smoke test and both cached coherency/benchmark configurations
pass with unchanged cycle counts. Actual ao486 protected-mode memory,
unaligned writes, REP MOVSD, DDR instruction fetch, reset and the DOS
probe's return to real mode pass at both 16 MB and 64 MB. The 64 MB probe
rejects a deliberately restricted 16 MB map. Physical timing of this
segment change and hardware testing remain pending.
