# Parallel system-memory address selection

75 MHz build #109 fits successfully but fails CPU setup by 2.376 ns.
An internal CPU path also fails by 2.287 ns, from `read.rd_cmdex[0]`
through the system-address priority mux to `tlb.linear[17]`.

The fourteen `rd_system_linear` cases are mutually exclusive. Their address
arithmetic is unchanged; selection now uses parallel masked terms and an OR
reduction instead of a priority chain. No registers, request enables, pipeline
cycles, or memory transaction ordering change.

`tests/run-system-address-proof.sh` proves the actual generated decoder against
the preserved priority expression for every input and arbitrary task-switch
address state. The only state register has the same update logic and receives
the proven-equivalent address. A deliberately wrong selector must fail.
Both checks passed in `simulation-20260922-224024-6afe7a`.

Build #110 (`quartus-20260922-224112-901b9e`) measures physical timing. A proof
of address equivalence does not establish timing closure or hardware speed.
