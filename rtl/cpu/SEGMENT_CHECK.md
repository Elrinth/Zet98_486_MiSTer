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
rejects a deliberately restricted 16 MB map.

The isolated 66 MHz fit with this change reports 59.55 MHz Fmax and
-1.642 ns worst setup, worse than the decode-only 61.08 MHz / -1.221 ns.
The former segment path is no longer the worst path; the new worst path
runs from read_commands through pipeline readiness and instruction decode.
This is a physical-fit regression, not a measured speed improvement.
The complete-core 50/60 MHz fits and hardware validation remain pending.

The no-retiming 66 MHz experiment reports 60.44 MHz Fmax and -1.395 ns
worst setup. Its critical path moves to write result / ECX through rd_eip.
This small improvement still fails 66 MHz; the production retiming setting
has not changed.

The Metadata60 complete fit also places late segment selection before an
address adder on its read-command-to-memory-request path. The six segment
base-plus-offset sums now have retained intermediate nets, so address
arithmetic is available before the final selection. All sums still wrap at
32 bits and selectors 5/6/7 retain GS behavior. The original reference's
4,637,520 cases, full CPU smoke test, cached coherency/benchmark tests and
16/64 MB protected-mode memory tests pass; cycle counts are unchanged.
FPGA timing and hardware validation of these retained sums remain pending.

## Virtual-access length decode

System descriptor/TSS reads select special word/dword lengths through the
full command decoder. Virtual memory accesses now use a separate length
expression before segment checking. The memory interface retains the original
length expression. Yosys proves both lengths equal for all command inputs
whenever read, read/modify/write or write-only virtual checking is active;
a deliberately wrong byte length produces a counterexample. Cached and
uncached full-CPU regressions pass with unchanged 576 bus transfers.

The complete 60 MHz fit of 80ed62f reports +0.084 ns on the worst CPU-internal
setup path, but the complete core still fails. The slow/cold corner's
-0.583 ns path runs from DMA address selection through the PC-98 memory map
and cache invalidation into instruction decoding. Palette-to-video transfer
also fails by -0.179 ns. This build was not loaded on hardware.

## Registered stack-pop selector

The PaletteTransfer60 complete-core fit reports a -0.198 ns CPU path from
`rd_cmd[4]` through the next-stack selector and segment checks into the TLB
linear address. `read.v` now predecodes the command-only part of that selector
beside the existing command register. Its two flag bits have the same reset,
flush, load, ready and hold priorities. Protected-mode gating remains live.
There is no additional instruction cycle or memory-interface change.

`tests/prove-stack-pop-predecode.py` checks the actual read-command decoder
against the new expression with unconstrained inputs, then uses temporal
induction on the actual command/flag register update blocks. Negative controls
with incorrect protected-mode gating and a missing flush both fail. The
simulation-only assertion also compares the registered result against the
original decoder on every CPU edge.

Cached and uncached full-CPU smoke tests pass with 576 bus transfers each.
The full-CPU cache regression passes configurations 00/10/11, including DMA
writes, CPU self-modification, upper-window bypass and ALU/VRAM/stack checksums.
The disconnected-DMA negative control fails as expected. With both caches,
the three kernels take 6392/3720/5268 cycles and 17/162/145 transfers, unchanged
from the prior implementation. This is a candidate timing improvement, not
a measured instruction-speed increase. Physical fitting remains pending.

## Registered global descriptor limits

The StackDisplay60 fit (`quartus-20260921-230252-980603`) reports a
-0.348 ns path from a global descriptor through limit expansion, stack-fault
checking and the memory bridge's byte-enable register. `global_regs.v` now
expands both global descriptor limits on their existing update cycles and
stores the results beside the original descriptors. Reset, update and hold
priorities are unchanged, with no additional instruction cycle.

`python3 tests/prove-global-descriptor-limits.py` runs Yosys temporal induction
against the actual module and the independent original limit expressions.
Both limits match for arbitrary reset, update enables and descriptor values.
Negative controls using the previous descriptor value or omitting the second
limit's reset are rejected with counterexamples. A simulation assertion also
checks both decoded limits on every CPU edge. This is not a measured
clock-frequency improvement.

Cached and uncached CPU smoke tests both pass with 576 bus transfers. Cache
configurations 00/10/11 pass the DMA, self-modification and ALU/VRAM/stack
checks with unchanged cycles and transfers; disconnected DMA invalidation
still fails. Actual CPU protected-mode tests and the DOS probe's return to
real mode pass with both 16 MB and 64 MB RAM. The oversized-memory negative
control is rejected. These tests ran with the limit-alignment assertion enabled.

The complete GlobalLimits60 fit (`quartus-20260922-003422-b6b4ca`, source
78318fc) still fails timing and was not deployed. Its worst setup slack is
-0.937 ns at the slow/cold corner: ECX through string-completion, write-debug
and pipeline-ready logic into instruction decode. At slow/hot, a CS-cache
path into the same decoder is -0.683 ns. The reported memory crossing is
-0.030 ns and video crossing -0.185 ns. All three fitted HPS peripheral
guards pass. These reports supersede any expectation that registered global
limits alone would qualify the complete core for 60 MHz.

## Current-SP selector at 75 MHz

Build `quartus-20260922-171436-e11515` moved the worst setup path to
`rd_cmdex[1] -> address_stack_pop -> segment checks -> TLB linear address`,
with -2.146 ns slack. `stack_pop_decode` now registers the opcode-only part
of this current-SP selector alongside `rd_cmd`, using the same priorities.
Its real-mode/virtual-8086-mode gating remains combinational. The original
read-command decoder remains the simulation reference.

`tests/run-current-stack-proof.sh` proves both current-SP and next-SP
selectors for arbitrary inputs and register-update histories, and rejects
wrong mode gating and missing flushes. Cached/uncached real-CPU regressions
retain 751/576 transfers and the same execution times. This does not yet
establish 75 MHz timing closure.
# Parallel read-segment faults

The 75 MHz build #100 critical path ran from CR0.PE through the stack segment
selection and combined fault logic into the TLB address register. The checker
now computes each segment's complete permission, length and limit fault before
selecting SS, ES or the prefix segment. Retained fault nets prevent synthesis
from moving shared checks back after the late selection. No cycles are added.
Selectors 6/7 retain the original GS access/length behavior without a limit
overflow check. `tests/run-segment-fault-proof.sh` compares all seven outputs
with the frozen previous implementation for unconstrained inputs, and rejects
wrong stack priority and off-by-one boundary mutations.

## 75 MHz redundant privilege gating experiment

Build #102's worst path starts at CPL and passes through the command word-length
decoder, per-segment length comparison and TLB request selection. The segment-only
word-length expression now omits the MOV-to-segment/LLDT/LTR and LMSW privilege
guards and LMSW mutex guard. Those guards still suppress the original virtual
request; no permission check or memory-interface length is changed.

`tests/run-segment-length-proof.sh` proves the actual command decoder's original
length equals the new segment length whenever virtual read, read/modify/write or
write-only segment checking is active. Every decoder input is unconstrained. A
wrong byte length is rejected as a negative control. This passed in
`simulation-20260922-194112-5a70b1`. Build #103 compiled but failed timing, with worst slack -2.487 ns versus
-3.117 ns in #102. This is an improvement in the worst reported slack, not a
75 MHz qualification or a measured hardware-speed improvement.
