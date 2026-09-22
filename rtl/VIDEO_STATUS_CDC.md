# Video status and floppy return crossings

The MeasureDebug60 fit (`498644c`, 2026-09-22) failed all-corner timing at
the floppy CPU-side return register and an HDMI vertical-sync status consumer.
The worst setup slack was -0.267 ns; the CPU-only report was positive. That
RBF was not deployed. These paths cross different clocks and require explicit
transfer contracts rather than treating adjacent PLL edges as one CPU cycle.

`sys_top` now samples `HDMI_TX_VS` through two preserved synchronizer stages
before its frame-wait and configuration-commit edge detectors use the level.
Previously, one detector compared its first sample directly with the raw
video-clock signal. The configuration detector also used its first sample as
functional data. Both consumers now operate entirely on the synchronized
level. HDMI output timing and the outgoing sync signal are unchanged; control
observations gain two system-clock stages.

`pc98-video-status.sdc` excludes only the launch-to-first-stage paths. It
requires the expected endpoint counts, includes physical launch duplicates,
and leaves inter-stage paths and all consumers timed. The same first-stage
contract covers the existing two independent retrace status synchronizers.
It does not exclude entire clock domains or multi-bit encoded control buses.

Buffered floppy return words already use held memory-domain data and a
two-stage completion toggle. The source captures its completed read before
raising completion; the consumer captures the held word on the edge that
releases WAIT. The source cannot replace it until a subsequent transaction.
`pc98-read-transfer.sdc` now constrains these two sixteen-bit bundles to the
same 5 ns maximum route used for CPU/GDC return words. Hold checks and all
WAIT/completion paths remain active. The additional `*_read_crossing` signals
are combinational aliases that permit transport-delay injection in simulation;
the hardware read protocol and its latency do not change.

`tests/run-video-status.sh` extracts the actual synchronizer and both consumer
blocks from `sys_top`, checks six system-clock rates and 24 VS transition
phases, and rejects bypassing the first stage. It also verifies that the
consumers do not reuse the raw signal or treat falling/constant-high sync as a
new rising edge. This simulation does not model analog metastability.

`tests/run-floppy-read-bundle.sh` injects 5 ns data routing and asserts another
5 ns of stability at the capture edge, over both floppy channels, six source
clock rates and 24 memory phases with continuous requests. An 80 ns late
bundle must fail. Existing floppy request and CPU/GDC read-bundle regressions
remain separate checks. `tests/test_video_return_constraints.py` executes the
production SDC under Tcl to check endpoint guards and exception scope. Fitted
endpoint resolution, timing and physical hardware remain separate requirements.

The corrected consumer test and all floppy/CPU/GDC bundle regressions passed
on 2026-09-22 in `build/simulation-20260922-084726-ce7f8f/tests.log` (exit zero,
no OOM, container removed). This includes 144 HDMI edge-phase/rate cases,
288 new floppy return phase/rate/port cases, both late-return negative tests,
and the existing request/stale-completion/readback negative tests. The three
Tcl guard tests also passed locally. A preceding test incorrectly expected
disabling configuration to wait for VS; the test now preserves the original
immediate-cancellation behavior. These checks do not establish FPGA timing.

The first StatusReturn60 compile stopped at the new endpoint-count guard,
before completing fitting. Its post-map TimeQuest inventory contains ten FDE
source/capture bits (0–9) and sixteen FEC bits (0–15). This matches
`diskemu_mister/FDemu.vhd`: only the data byte, mark flag and MFM flag are used;
the six unused upper FDE bits are synthesized away. The guard now requires
those exact live widths. Its 5 ns bound is unchanged. The revised Tcl tests
match actual endpoint names against an inventory and reject both missing and
unexpected FDE bits, rather than assuming every memory bus remains 16 bits.
Evidence is retained in `build/quartus-20260922-085654-c05616/endpoints.log`.

The next fit (`build/quartus-20260922-091323-ca114d`, source `5a5ea82`)
completed routing and assembly, then exposed three Fitter-created FDERDAT
copies in final timing. The guard now validates all logical bit indices on
both ends and includes every copy in the unchanged 5 ns bound. It rejects
missing bits even if other bits have duplicates. Seven Tcl tests pass,
including the actual ten-source/thirteen-capture FDE inventory.

Production TimeQuest was rerun on that existing routed database with only
this guard correction overlaid. It completed successfully; all reported
setup/hold/recovery/removal/pulse-width checks passed at every available
corner. Minimum slack is 0.066 ns (HDMI scaler), and the slow/hot system
domain setup margin is 0.380 ns. The pixel clock uses a global clock network
and the host-snapshot endpoint guards resolve. Original failed reports remain
in the source snapshot; successful reports are in `timing-copies/` and
`copies.log`, with `copies-result.json` and `timing-check-copies.json`.

SuperStation One then passed the 2,048-record GRCG diagnostic (see
`graphics/GRCG.md`) and CPU benchmark v3 with correct ALU/RAM/stack checksums.
In ten DOS seconds per kernel it completed 286/152/114 blocks, compared with
247/130/102 on FullFont50. These are approximately 15.8%/16.9%/11.8% gains;
they are not game frame-rate measurements. Private captures and screenshots
are in `build/hardware/status-return60-validation/`.
