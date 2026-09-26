# Local direct-load admission experiment

This is self-authored CPU simulation coverage. It contains no game or private
firmware payload, and does not alter `rtl/vendor/z486/z486.sv` or deploy a core.

The existing direct-load path can retire a cache hit or submit a cache miss
while the architectural segment checker is disabled. The retained limit-zero
control and its narrow direct-load-disabled comparison demonstrate that bypass.
They do not demonstrate the cause of original Doom's runtime failure.

`make_vipt_segment_candidate.py` generates a separate simulation CPU. It admits
a direct load only when the issuing instruction's masked effective offset and
last accessed byte are within that instruction's descriptor limit. The sum is
33 bits so wrapping past 4 GB cannot count as an in-range access. A rejected
shortcut follows the existing microcode exception path. It does not feed an
older or younger token's offset into the shared architectural fault checker.

Decoder widths are encoded 0/1/2 for 1/2/4 bytes. The first experiment mistakenly
used the size code as bytes-minus-one; the dword crossing test rejected it. That
experiment was discarded. The corrected mapping is 0/1/3.

`make_vipt_segment_cpu.py` creates independent assembly expectations for byte,
word, dword, MOVZX, MOVSX and register-destination ADD memory operands. Current
coverage includes aligned/unaligned, 16-bit address truncation, page-granularity
limits, exact valid boundaries, crossings and wholly outside offsets, with
cache prewarming and cold controls. An adjacent valid load uses GS while the
tested access uses a nonzero-base FS descriptor.

Invalid cases require vector 13, error code zero, the exact saved fault EIP,
unchanged destination register and arithmetic flags, suppression of the
following store, and successful IRETD recovery. Other exception vectors fail.
Valid cases check independently computed data. Simulation traces distinguish
direct admission and actual hit/miss coverage; prewarming does not imply a hit
for a wide access crossing the fast path's supported alignment boundary.

`run-z486-segment-admission.sh` has a 600-second outer deadline with a 10-second
termination grace. Evidence lives in `/project/segment-admission-evidence` and
must be archived with the complete run state/logs before container removal.

The initial qualification plan called for overflow, real-mode, stack-segment,
descriptor-change, token-overlap and general CPU regression coverage. Results
and remaining gaps are recorded below. The added comparison lies on an
admission path; FPGA area/timing are unknown. This is not a hardware-qualified
correction or a Doom fix.

Additional completed local coverage (2026-09-25):

- `make_vipt_segment_edges.py`: 30 cases pass for 4 GB offset overflow, precise
  stack-segment `#SS`, and reloaded FS descriptors with smaller/larger limits or
  changed bases. Run `135841-55db2e`; 63 evidence files archived.
- `make_vipt_segment_real.py`: 18 real-mode boundary/address-size cases pass.
  This control deliberately discards its real-mode exception frame; it does not
  claim precise-frame/IRET coverage beyond the protected-mode suite. Run
  `140522-8f2621`; 39 evidence files archived.
- `run-z486-segment-regression.sh`: candidate passes CPU/cache/64 MB regressions,
  640,000 forwarding checks, mode transitions and protected CRC windows with
  the corrupt-table negative. Run `140152-8d58a7`; original and candidate source
  plus four complete logs archived. Only the disposable `/project` snapshot
  was changed for these regressions.
- `make_vipt_segment_overlap.py`: four adjacent-load cases pass, but no
  `SEG OVERLAP` or `SEG REPLAY` trace was observed. These do **not** prove
  simultaneous-token coverage. Run `140807-ccf1a6`; 11 evidence files archived.

All four containers were removed after archival. Production CPU remains
unchanged. Next investigate admission timing and actual token overlap without
forcing internal states that production cannot reach. The prototype adds a
33-bit last-byte sum and limit comparison after the issuing effective address;
`d2_vipt_candidate` feeds `d2_ready_tail` and issue control. That dependency is
a timing risk, not a measured timing failure. Isolated synthesis or an
equivalent comparison with earlier descriptor-side work can help assess it;
neither substitutes for complete-profile fitted timing checks.

## Isolated comparison experiment

`vipt_segment_compare.sv` compares the tested 33-bit end-offset formula with bytewise unsigned comparison and descriptor-side limit-minus-one/two endpoints. All input combinations are SAT-proven equivalent, including overflow and all four width codes; missing-endpoint and inclusive-boundary mutants fail. Final syntax-compatible proof: simulation-20260925-143032-aea7c1. The parallel form is not yet integrated into the CPU.

Timing bundle segment-admission-timing-r4 compares two identical register wrappers on the same device/seed/clock, with sequential fits and all-corner reports. It is not a deployable core and cannot establish full-core timing or Doom causation. R1 shell CRLF and R2 parser/virtual-node failures were archived before correction.

R3 successfully fitted the sum form but reporting rejected the physical register count: Quartus duplicated 13 limit registers, documented in its Fitter report. R4 reuses that exact completed fit and requires every original input bit plus only explicitly named DUPLICATE registers; all copies participate in timing. This avoids discarding duplicated paths or rerunning the completed fit.

R4 completed both isolated fits and four operating corners, preserving 220 files including full databases before container removal. The sum form uses 50 ALMs/80 physical registers; the parallel form uses 89/78. Worst offset-group data delay is 7.152 ns versus 6.893 ns; worst limit-group delay is 4.697 ns versus 7.476 ns. All reported setup slacks are positive; global isolated hold minima are +0.223/+0.228 ns. Worst start bits differ, and these are isolated group maxima rather than matched full-core paths. The small offset improvement does not justify adopting the larger parallel form. Neither form has been qualified in the full CPU timing path; production remains unchanged.

## Natural replay and overlap coverage

PC98 stages every memory ModR/M effective address (`d2_ea_needs_split`), so adjacent ordinary loads need not overlap in EX. A load issued behind an older store may instead enter the replay path. New self-authored programs exercise this using ordinary stores and FS/GS loads; monitors never force internal state.

- `154236-54f83e`: 16 store/load cases PASS, with 22 accepted replays and 12 valid-load overlaps across 12 cases. Store bytes, load destinations, precise later faults and return state pass. All 35 evidence files archived; container removed.
- `154504-bc9b83`: eight immediate younger-fault cases PASS, but no replay or simultaneous older EX was observed. All 19 evidence files archived; container removed.
- `154715-603505`: 32 instruction-placement cases (0–15 NOP bytes after real store/load traffic) PASS. Trace records 64 replays and 32 valid-load overlaps in the preludes, but zero rejected-younger-with-older-EX events. All 67 evidence files archived; container removed. Thus valid token ownership has measured coverage; simultaneous fault overlap does not.

These results supersede the earlier blanket claim that overlap was unobserved, but do not prove that every overlap/fault combination is unreachable or correct. Production remains byte-identical to B161. The 33-bit admission guard is still a simulation prototype; full-core fitted timing and hardware behavior are unqualified. No Doom causation is established.
