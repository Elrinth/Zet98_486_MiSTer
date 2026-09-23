# TLB address selection

The generated address update combined request priority, alignment faults,
flushes, double-write page handling, and register hold in one priority chain.
At 75 MHz, build #110's worst CPU path passed through this chain after the
write-stage stack checks.

The address data now uses six mutually exclusive masks: write, check, read,
code, next page, and saved double-write address. Late alignment and flush
conditions control the address register's enable. They do not control its
data mux. Request priority and the exact hold behavior are preserved. There
is no extra cycle, speculative register update, or change to the TLB FSM.

`tests/prove-tlb-linear.py` compares the actual RTL to the frozen original
expression for arbitrary addresses and request/fault/flush qualifiers in
every state encoding. It also proves the actual reset/update/hold block by
induction. Mutations remove write/read alignment checks, change priority or
the next-page increment, and remove the register enable; each must fail.

Run `tests/run-tlb-linear-proof.sh` in `zet98-formal-tests:latest` with
`-AdaptersOnly`. Run the mixed-image CPU and 16/64 MB protected-memory tests
afterward. Routed all-corner timing, and then MiSTer qualification, are still
required before calling the 75 MHz build usable.
