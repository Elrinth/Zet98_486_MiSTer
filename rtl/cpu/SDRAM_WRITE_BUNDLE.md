# CPU graphics writes into SDRAM

The former CPU write path combined a CPU byte-lane/reset mux, bus arbitration,
GRCG tile/mask logic and the SDRAM state mux across CPUCLK and memclk. The
60/100 MHz clocks can have adjacent edges just 3.334 ns apart; the measured
path took 8.174 ns before clock skew and failed by 5.898 ns.

The CPU GRCG instance now produces a static set word for each plane and a
16-bit preserve mask. SDRAMC captures these 80 bits on the same CPU edge as
the request metadata. Its existing three-stage request admission captures
the held bundle into memclk registers. Fresh plane reads are merged there:
`set | (read & preserve)`. Ordinary writes have a zero preserve mask. The
separate GDC drawing port now uses the same set/preserve transfer, with
its own request, admission registers and completion handshake.

This adds no SDRAM command or transaction state. It also avoids latching an
RMW result before its read has happened. Only the source-to-admission bundle
has a 15 ns maximum-delay constraint. Admission is at least 20 ns after its
launch, and the source stays held until a later CPU request. The live memory
merge, request/ACK controls, address, reset, and normal hold checks remain
timed. Other inherited CPU/SDRAM clock crossings still need review.

`tests/run-sdram-write-bundle.sh` checks 9216 transactions: six operation
types, all byte and plane masks, varied data, 20/40/50/60/90/100 MHz CPU clocks
and four relative phases each. It injects 15 ns bundle delay and requires
at least 5 ns stability at admission. An 80 ns delay must fail. These clock
rates exercise the controller protocol only; they do not establish CPU or
FPGA operation at those rates. The legacy controller's 1536 transactions and
4096 GRCG plane-result comparisons also pass. A test-model change keeps the
fourth SDRAM beat driven through its sampling edge instead of releasing it
at the same simulation timestamp.

Memory-ready reset now releases on two CPU edges for its CPU-clocked
consumers. Only the reset-release synchronizer inputs are excepted; their
outputs remain subject to recovery/removal checks. The common reset module's
phase/stopped-clock tests pass. The 60 MHz integrated fit
`quartus-20260921-132727-3d85bc` completes with 34620 ALMs, 453 RAM blocks and
66 DSPs. It still fails nine reported checks, worst -3.120 ns. The former
write path is no longer the worst path; memory-domain read data now feeds
deep CPU execution logic across an adjacent 3.332 ns clock-edge interval.
The full CPU-clock domain fails by -0.575 ns and CPU-internal setup by
-0.202 ns; placement changed the earlier prefetch-only +0.030 ns result.
Memory-ready reset recovery is fixed, but a separate video-reset recovery
path still fails by -0.080 ns. This RBF has not been deployed.

The next change captures all four CPU-visible read words on the same CPU
edge that already asserts CPUACKb. The bridge samples ACK and data together
on its following edge. Internal RMW still uses the fresh memory-domain
words; the legacy mode retains its live read outputs. This adds neither a
memory command nor a completion cycle. It introduces no new timing
exception: read data and completion controls remain normally timed.
Varied per-transaction/per-plane read data is checked at ACK assertion;
a deliberately one-cycle-late capture must fail. Integrated fitting and
hardware validation of this read change remain pending.

The write-bundle/prefetch combination at 50 MHz completes in
`quartus-20260921-135403-d6bfcb` with no reported negative timing check
(minimum +0.056 ns), 34160 ALMs and 453 RAM blocks. Board-I/O constraints
remain incomplete. Its Bundle50 hardware test passes 100 FM timer interrupts.
This build precedes the read-capture change. The latter's 60 MHz fit in
`quartus-20260921-141137-e39c88` has 17 reported failing checks, worst setup
-2.289 ns from the separate GDC drawing write path. CPU-internal setup
passes at +0.256 ns; CPU-clock-domain setup still fails by -0.033 ns.
Other video/hold/removal failures remain. Neither 60 MHz RBF was deployed.

The GDC change captures its source with SUBREQ and its memory-side payload
with SUBJOB. Completed reads are registered on the existing SUBACK edge.
`tests/run-sub-write-bundle.sh` passes 9216 buffered and 1536 legacy drawing
transactions, plus deliberately late write/read negative controls. The four
legacy completion times exactly match the corresponding buffered cases.
CPU, video-SDRAM and actual GRCG/data-bus regressions also pass. Neither a
memory operation nor an acknowledgement cycle is added. Only the held
80-bit source-to-admission bundle receives the same bounded 15 ns constraint;
request, completion, read results and normal hold checks remain timed.
Integrated timing and hardware verification of this GDC change are pending.

The floppy emulator (FDE) and image-transfer (FEC) ports also capture their
40-bit address/data payload with request acceptance, then with memory-side
JOB admission. This removes the live seek/address calculation from the
memory state-machine path. Return words are captured with the existing
WAIT release; no memory command or wait cycle is added. The 15 ns constraint
covers only the held payload registers. Tests pass 12,288 buffered and 2,048
legacy requests across both ports, six source rates/four phases, poisoned
live pins after acceptance, and four deliberately late payload/read controls.
The CPU, drawing and scanout regressions also pass. FPGA timing and hardware
validation of this floppy change remain pending.
