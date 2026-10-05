# Optional unregistered address calculation

`-Z486PipelineRegs 0` removes the remaining optional address calculation
stage relative to the performance candidate's profile 2. This is an existing
CPU parameter, now exposed in the full memory regression runner through
`Z486_PIPELINE_REGS` (default 2). Default FPGA settings remain unchanged.
Physical timing and application performance require hardware qualification.

Current hardware status: **PR0 is not qualified**. The completed seed-12
bitstream panics during Linux boot and stalls during DOS initialization.
Keep PR2 for the tested performance candidate; details and evidence follow.

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

## Refreshing a complex address after an ALU commit

Expanding the profile-0 comparison to seeds 1-40 exposed another dependency
in seed 36, block 1020. After `add edx,[memory]`, an independent load and
`lea esi,[eax+edx*2+230]`, a saved partial address still used EDX before the
ADD. With EAX `5156e75ah`, old EDX `3a0af086h` produces the observed wrong
address `c56cc94ch`; committed EDX `e3f5d957h` produces the required
`19429aeeh`. Profile 2 passes that seed.

The split-address readiness bit now stays clear when a matching VIPT ALU
commits. That producer does not forward its WB result into the address
reader, so the partial sum must be captured again on the following edge.
This adds no register or ALU-result bypass. Ordinary forwarded-load and
deferred-shift address preparation keeps its existing behavior.

`vipt_alu_complex_ea_probe.asm` independently checks the value across cold
and warm repeated instruction alignments. It fails before the correction
in profile 0 and passes afterward. Both corrected pipeline configurations
pass all 40 differential seeds (1,200 blocks each), matching all GPR records
and 384 KB RAM per seed. Profile 0 also passes the full two-mode memory
suite and both retained dependency probes. Final results are under
`build/pipeline0/final-pr{0,2}-*`.

Both full two-mode memory suites pass after the split-address correction
(84 CPU cases per profile, including both new regressions). All 80 original
profile-2 cases still retain exactly their previous cycle/instruction/active
counts. All 40 differential seeds pass in each profile.

The final PR0 source also passes all twelve non-mutating retained suites:
GPR forwarding, RMW reload, smoke/cache/extended-memory/UART, protected-mode
payload, PIT GDT and LDT, LSS stack, stack allocation, unreal CS, prefetch,
RAM initialization and IDE BIOS read/write. This run explicitly uses PR0,
32 KB instruction / 8 KB data cache and native-framebuffer-only defines.
Evidence: `build/pipeline0/retained-pr0-summary.log` and `retained-pr0/`.

The first final-source PR0 fit (seed 6, 90 MHz) exceeds capacity at 4,205
LABs versus 4,191 available. Its failed report is retained at
`build/icache32-fast90/failed-fit.rpt`; it produced no usable RBF. A seed-12
retry uses the same functional source. Simulation performance is not yet
an FPGA performance result.

With the same 32/8 KB and native-framebuffer-only configuration, both PR0
and PR2 also pass the full-CPU upper-RAM cache test using a fresh GHDL
translation of the real PC-98 cache policy. Native writes, bank-AB alias
writes, DMA, bank-89 remap/restore and ROM bypass pass. All three controls
that disconnect alias/DMA/remap invalidation are rejected. Evidence:
`build/pipeline0/upper-summary.log` and `upper-pr{0,2}.log`.

The seed-12 PR0 fit completes at 41,501 ALMs, all 4,191 LABs, 551 M10Ks
and 50 DSPs. Worst slack is -9.380 ns (11 negative checks), within the
user's allowance; pixel-clock, HPS peripheral and SDRAM FEC audits pass.
However, this bitstream is **not qualified**: two fresh Linux boots panic
at different kernel locations (`c02be82c` and `c01239d7`), and DOS remains
at the Z98MEM initialization banner for over 60 seconds. No Doom speed
claim is made for PR0. Physical timing versus a remaining RTL dependency
has not been isolated. Source is `9d74068`; evidence is in
`build/icache32-fast90-s12/`, with RBF SHA-256
`7f4fea2ea1575d1dfabaa7df73698fed912ef873d8f5ea46f00a1b4480b3029a`.
A 90 MHz PR2 build of the final source is queued to qualify the retained
pipeline configuration including both dependency guards.

After these hardware failures, another 400 differential seeds (41-440)
pass on the same final PR0 RTL: 1,200 blocks per seed, with every GPR
record and the 384 KB RAM dump matching Unicorn. Together with the original
40 seeds, the total is 440. This broader run does not reproduce or resolve
the hardware failure. Evidence: `build/pipeline0/hardware-failure-fuzz/`.
The failed fit also adds a -0.038 ns slow-minus-40C hold violation on the
system-clock output, versus +0.228 ns in the working PR2 build. The ignored
assignment lists match. Neither comparison establishes a root cause.

Detailed post-fit reports locate the extra hold violation on the HPS-DDR
to PEGC scanout line-buffer path, not an internal CPU register path. The
worst setup path is bus-bridge `owner.IO` to prefetch `win_d1_r[9]`
(-9.380 ns); the worst path wholly inside the CPU goes from the prefetch
window to a decoder entry-ROM address (-8.949 ns). These reports narrow
future timing work but do not explain the hardware boot failures.
