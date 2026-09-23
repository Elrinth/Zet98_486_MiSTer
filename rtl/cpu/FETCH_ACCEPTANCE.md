# Early full-fetch comparison

Build #111's worst 75 MHz path starts at memory-write completion, travels
through pipeline readiness and the decoder capacity mux, then compares that
capacity with the available fetch length before updating the prefetch FIFO.

`decode_regs` now compares both completed capacity candidates with
`fetch_valid` before selecting on late `consume_enabled`. The one-bit
`dec_fetch_fits` result passes through `decode` and `pipeline` to `fetch`,
which uses it for full and partial acceptance. The byte capacity remains
available for partial-count updates and instruction-length fault handling.
No buffering, instruction cycle, accepted byte, or FIFO policy changes.

The hardware form uses the same actual Cyclone V three-input mux as the
buffer's existing final selection. `tests/prove-decode-buffer.py` now proves
the new flag against the original capacity comparison for every arbitrary
buffer state and input, alongside byte/count equivalence. The exact equality
boundary is a new negative control. It also checks the actual instance
connections and fetch consumers. The boundary/history test compares this
flag against the legacy capacity on every check.

Prepared after build #112's source snapshot. Formal equivalence and five
negative controls pass in `build/simulation-20260923-010953-6ca15c`.
The actual Cyclone V mux passes 1,024 boundary combinations and 10,000 history
cycles; cached/uncached CPU and 16/64 MB protected-memory tests pass in
`build/simulation-20260923-011304-e5a7f2` (that run subsequently stopped on a
shell line-ending error in the peripheral test, corrected separately).
Build #113 compiles at 100 MHz / 64 MB, with -6.063 ns worst reported slack
(within the user's -12 ns experimental limit). The CPU, physical-memory,
graphics and FM interrupt hardware diagnostics pass. This is board evidence
for the experiment, not a timing-closure claim.
