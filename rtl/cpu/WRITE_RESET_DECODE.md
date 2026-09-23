# Write-stage pipeline reset predecode

At 75 MHz, build `quartus-20260922-163433-508757` had a 12-level path
from `wr_cmd[5]` through `wr_req_reset_rd`, the pipeline stall chain, and
the instruction buffer. Its cold-corner setup slack was -2.561 ns.

`write_reset_decode` computes only opcode/substep predicates when the
write-stage command is loaded. The selectors use the same priority as
`wr_cmd`: reset, flush, load, retire, hold. All selected predicates are false
for `CMD_NULL`, independent of the retained substep. Unconditional reset
cases are combined before the register boundary. Unused individual
selectors can be removed by synthesis.

Completion, fault, REP-count and other dynamic conditions remain in
`write_commands`. No pipeline cycle, reset pulse, or instruction retirement
is added or removed. Address/data selection for string writes is a separate
optimization; its write-permission checks remain unchanged.

The modified generated reset assignments in `autogen/write_commands.v`
must be retained if that file is regenerated. The original conditions and
five reset outputs are frozen in `tests/reference/write_reset_legacy.vh`.
`tests/run-write-reset-proof.sh` proves all five outputs for arbitrary
inputs and uses induction on the actual command/selector register updates.
It also rejects deliberate wrong-selector and missing-flush mutations.

Run `tests/run-write-payload.sh` for payload equivalence and cached/uncached
CPU regressions, including interrupts, reset and REP boundaries. These
functional checks do not establish 75 MHz timing closure; routed timing at
every operating corner and subsequent hardware tests are still required.
