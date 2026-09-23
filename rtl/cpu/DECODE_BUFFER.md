# Instruction buffer count selection

HostSettings60 at source b700d62 fails its cold CPU corner by 0.151 ns.
The path runs from instruction bits through length decoding, buffer capacity,
accepted-byte selection and a final addition into `decoder_count`.

The new count calculation computes the prefix/fetch limit independently of
the late consume count. If the buffer capacity limits the refill, the resulting
count is exactly 12: `(count - consume) + (12 - count + consume)`, modulo 16.
Otherwise it selects the independently computed `count - consume + available`.
This removes the final adder from the capacity-comparison path. Fetch acceptance,
byte shifting, resets, stalls and pipeline cycles are unchanged. The identity
also holds for unreachable/underflow four-bit encodings.

`tests/run-decode-buffer-proof.sh` uses Yosys to compare all outputs and next
state against the original ao486 buffer for arbitrary shared state and inputs.
It checks the actual sequential clock/reset assignments before removing them
for the combinational proof. Identical reset state and arbitrary-state
one-step equality establish equivalence for every subsequent history.
All 96 buffer bits, four-bit counters, acceptance and control inputs are
unrestricted. Wrong capacity, ignored stalls and ignored decode resets must
produce counterexamples. All pass. An earlier multi-cycle unrolling timed out;
that timeout is not treated as evidence.

`tests/run-decode-buffer-cpu.sh` also passes 262,144 exhaustive count/consume/
prefix/fetch/stall/reset combinations and 10,000 sequential cycles, then the
uncached and cached real-CPU instruction/interrupt/REP regressions (576 and
751 bus transfers). The cached run covers CL/CH writes, zero/one counts,
16/32-bit address sizes and crossing the count high-word boundary.

Logs: `build/decode-buffer-count-formal-combinational.log` and
`build/decode-buffer-count-cpu-regression.log`. Physical timing and hardware
performance of this optimization remain unverified until a fresh fit and
benchmark; these proofs do not establish a higher usable CPU frequency.

## Instruction-buffer preservation experiment

Build #104 failed at -2.550 ns on a global-parameter/read-exception/readiness
path into the instruction buffer. `decode_regs.v` now retains the two complete
104-bit consume/stall results before readiness selection. This preserves the
existing architecture and clock count while preventing logic sharing across
that boundary. Arbitrary-state next-step equivalence and three mutations passed
in `simulation-20260922-205217-af8a0c`. Build #105 is testing routed timing.

## Explicit Cyclone V ready mux

Build #105 produced exactly the same timing as #104; keep attributes alone did
not change the result. They have been replaced by an explicit 104-bit bank of
Cyclone V combinational cells with `dont_touch=on`. Stalled and consume results
feed inputs A/B; the late ready control uses F. The LUT mask is
`64'hCACACACACACACACA`, giving B when C is high and A when C is low.
No new state or pipeline latency is introduced. Non-synthesis simulation keeps
the equivalent portable mux expression.

The actual Intel Cyclone V model is extracted from the existing Quartus image
by `scripts/test.ps1` and hashed with the other simulation libraries; it is not
redistributed in this repository. The buffer SAT proof reads that real model,
proves all arbitrary buffer states/inputs, and rejects a swapped-LUT-arm
mutation as well as the original three negative controls. Passed in
`simulation-20260922-212535-fa236e`. Run the proof with the formal image but
without `-AdaptersOnly`, so the model is supplied. The ordinary buffer test
also simulates the `ZET98_CYCLONEV_READY_MUX` branch using the same vendor model.

The direct vendor-model simulation passed 1,024 boundary combinations plus
10,000 sequential cycles in `simulation-20260922-213332-7d540e`; both CPU
regressions retained their original 576/751 bus transfers and 48.630/73.250 us
execution times. The portable exhaustive 262,144-case run passed earlier; its
duplicate exhaustive vendor simulation was stopped in favor of this smaller
event test, alongside the universal formal proof. Build #106
`quartus-20260922-213504-ed1635` was subsequently stopped as described below.

Build #106 was stopped after mapping: the implicit `SYNTHESIS` branch did not
produce identifiable ready-mux atoms and the buffer mapping was identical.
The top-level ao486 build settings now explicitly set `ZET98_CYCLONEV_READY_MUX=1`; formal and event
tests explicitly select the same branch. A full timing run is still required.

Quartus 17 rejects VERILOG_MACRO inside a QIP (build #107 stopped immediately).
The setting is applied in scripts/build.ps1 alongside ZET98_AO486 instead.

Build #108 selected the primitive but failed ALM placement: not all LUT inputs
were routable. The new compact three-input mapping uses A/B for payloads, C for
readiness, and leaves unused atom ports unconnected. Universal vendor-model
equivalence and all four negative controls pass in
`simulation-20260922-220411-661f34`. Physical fitting remains to be checked.
