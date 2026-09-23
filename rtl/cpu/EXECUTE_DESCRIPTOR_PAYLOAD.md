# Execute descriptor payload timing

Build #103's worst 75 MHz path (-2.487 ns) begins at CS granularity,
passes through a limit/fault decision and gates descriptor data before the
cached descriptor-limit register. The original execute decoder always writes
`glob_descriptor` to descriptor 2. Descriptor 1 receives `ss_cache` for the
protected CALL first step, and `glob_descriptor_2` for other enabled writes.

The execute stage now selects those payloads without the late fault gates.
The original decoder still supplies all write enables, exception signals and
pipeline control. Payload values while disabled are intentionally unspecified;
no new pipeline stage or CPU cycle is added. Read-stage descriptor priority is
unchanged. Simulation assertions compare enabled values to the original decoder.

`tests/run-execute-descriptor-proof.sh` proves the actual production expressions
against that decoder with every input unconstrained, plus the descriptor-limit
register invariant. Wrong stack/descriptor sources, stale limits and missing
limit reset are rejected. Passed in simulation-20260922-201520-12634d.

Full CPU/protected-memory regression and routed 75 MHz timing are required;
this proof alone does not qualify the clock frequency.

The focused CPU and 16/64 MB protected-memory checks passed in
`simulation-20260922-201602-c2a480`, including REP and the DOS probe. The
optional broader cache benchmark was stopped to proceed with the requested
timing run; that entire suite must not be described as passed.
Build #104: `quartus-20260922-202020-c3b74d`, timing failed: CPU hot -2.550 ns, CPU cold -2.387 ns, HDMI cold -0.080 ns.
This is not a qualified 75 MHz build.
