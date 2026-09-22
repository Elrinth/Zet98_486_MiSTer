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
