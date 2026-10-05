# Optional unregistered address calculation

`-Z486PipelineRegs 0` removes the remaining optional address calculation
stage relative to the performance candidate's profile 2. This is an existing
CPU parameter, now exposed in the full memory regression runner through
`Z486_PIPELINE_REGS` (default 2). Default FPGA settings remain unchanged.
Physical timing and application performance require hardware qualification.

## Destination dependency exposed by the shorter pipeline

With profile 0, 486 differential seed 4 failed after block 921. A cached
`xor eax,[memory]` followed by `mov al,[memory]` and `lea ecx,[eax+5]` produced
`10139c55h` instead of `fc2d7655h`. The byte load captured EAX's old upper
lanes on the same edge that the older memory-ALU operation committed its
new result. The architectural byte write was correct, but its registered
forwarding value retained stale upper bits. The extra address stage in
profile 2 hid this sequence.

A destination dependency now holds a younger partial load or memory ALU
for one issue cycle when an older VIPT ALU in EX writes that register.
Its destination capture then sees the committed value. Full-width MOVs and
independent destinations retain overlap. This reuses registered destination
identities and adds no ALU-result mux to the address path.

`vipt_alu_partial_load_probe.asm` checks low-byte, high-byte and word loads
followed by LEA, plus dependent memory ALUs, at varied instruction alignments
with cold and warm passes. The original profile-0 implementation fails this
probe; profile 2 passes it. The correction passes with profile 0 in both
buffered-read modes, together with all 52 stack page-fault cases, other memory
faults, reset, CPU speed settings, driver initialization and self-modifying
code. Eight 486-enabled differential seeds of 1,200 blocks each match Unicorn
for every GPR record and 384 KB RAM. Evidence is in `build/pipeline0/`.

At 32 KB instruction / 8 KB data capacity, profile 0 with the fix changes the
stack-allocation probe from 10,819 to 10,253 cycles (5.52% more throughput),
the graphics probe from 35,991 to 35,611 (1.07%), and the self-modifying-code
stream from 416,292 to 409,368 (1.69%). The 64,000-byte RAM/framebuffer workload
stays at 1,053,345 cycles. Each comparison executes the same instruction count.
These synthetic measurements are not Doom results or proof of a usable FPGA
clock frequency.

The corrected profile 2 also passes the complete two-mode memory suite and
eight 486 differential fuzz seeds. All 80 existing CPU cases retain exactly
their previous cycle, instruction and active-cycle counts. The new probe
executes 3,871 instructions in either profile, taking 26,183 cycles with
profile 2 and 25,117 with corrected profile 0.
