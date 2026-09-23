# Write-stage stack-width and resume-flag predecode

75 MHz build #110 (`quartus-20260922-224112-901b9e`) failed setup at
-2.665 ns hot and -2.642 ns cold. Its worst paths ran from `wr_cmd` through
stack-push width/fault logic into the TLB and through `rflag_to_reg` and debug
handling into execute-stage readiness and global registers. HDMI also failed
cold setup by 0.276 ns; this CPU change does not address that path directly.

`write_control_decode` registers ten opcode/substep predicates alongside
`wr_cmd`, with the same reset, flush, load, retirement, and hold priority.
Six select the resume-flag source; four select stack-push width controls.
Operand size, descriptor/gate width, flags, and fault conditions stay live.
There is no added pipeline stage, instruction cycle, or changed request enable.

The three original output expressions and their conditions are preserved in
`tests/reference/write_control_legacy.vh`. `tests/run-write-control-proof.sh`
compares all outputs for arbitrary inputs and proves the real register-update
invariant by induction. Wrong selector, missing flush, and reversed load/retire
priority mutations must fail. Run it using the formal image and `-AdaptersOnly`.
Run `tests/run-write-payload.sh` separately in the mixed simulator image for
cached/uncached CPU, interrupts, reset, and REP-boundary regression checks.

Preserve the changed generated expressions in `autogen/write_commands.v` if
regenerating that file. Functional equivalence does not establish timing closure;
the fitted build must pass every timing corner before hardware qualification.
