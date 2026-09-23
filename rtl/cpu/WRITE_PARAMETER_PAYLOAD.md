# Task-switch parameter payload

Build #111 exposes a -2.199 ns path from the write-stage command through the
task-switch parameter enable and a long payload mux into `glob_param_1`.
The original payload repeated access/ready controls for each segment source.

The payload now selects directly from the seven task-switch substeps. These
substeps are mutually exclusive, so a parallel masked mux can compute the
data while the original `wr_glob_param_1_set` decision settles. The enable,
fault/ready conditions, read/execute/write arbitration and register reset/hold
are unchanged. Payload values outside enabled updates are intentionally
unspecified to the consumer.

`tests/run-write-parameter-proof.sh` in the formal image compares the real
decoder against the frozen original payload whenever its write enable is
active, with every input unconstrained. It also proves the global-register
priority/hold next value for arbitrary competing read and execute writes,
and checks the actual consuming RTL structure. Wrong task data and step
selectors must fail. CPU and protected-memory regressions remain required.

Prepared after build #112's snapshot. Enabled-payload and global-register
priority/hold proofs plus both negative controls pass in
`build/simulation-20260923-010953-6ca15c`. Cached/uncached CPU, REP and 16/64 MB
protected-memory tests pass in `build/simulation-20260923-011304-e5a7f2`.
Build #113 compiles at 100 MHz / 64 MB, with -6.063 ns worst reported slack
(within the user's -12 ns experimental limit). The CPU, physical-memory,
graphics and FM interrupt hardware diagnostics pass. This is board evidence
for the experiment, not a timing-closure claim.
