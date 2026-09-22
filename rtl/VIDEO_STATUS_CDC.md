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
