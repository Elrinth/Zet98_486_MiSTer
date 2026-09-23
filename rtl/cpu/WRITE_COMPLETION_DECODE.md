# Write completion predecode

The 75 MHz build #100 cold-corner path ran from the write command through
`wr_not_finished`, interrupt/debug gating and decode-stage retirement. The
completion decoder now registers opcode-only predicates alongside `wr_cmd`.
The 86 unconditional opcode terms become one flag; the remaining opcode
predicates qualify the original live conditions. There is no extra cycle,
and fault, interrupt, memory completion and REP controls remain live.

`wr_finish_select` uses the same reset, pipeline flush, load, retirement and
hold priority as the command. CMD_NULL normalizes every flag to zero, because
flushing the command retains its substep register. This is necessary for the
registered selector invariant; substep-only predicates are immaterial when
the command is null.

`tests/run-write-finish-proof.sh` proves the completion output against the
frozen original expression for every decoder input and proves the actual
register-update invariant by temporal induction. It also rejects wrong
selector and missing-flush mutations. Preserve this optimization when
regenerating `autogen/write_commands.v`; the proof detects its removal.

Before any hardware qualification, rerun the CPU, cached REP, segment access
and protected-memory regressions, then require all-corner post-fit timing.
