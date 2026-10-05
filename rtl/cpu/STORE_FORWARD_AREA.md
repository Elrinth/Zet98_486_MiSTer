# Shared byte selection for data-cache store forwarding

The three-entry store queue forwards queued bytes to five destinations:
cache-hit loads, bypass loads, ordinary fills, wide-line responses and
wide-line installation. The previous implementation walked the queue
separately with each destination's original word.

The replacement walks the queue once for the requested DWORD and once for
the fill DWORD. Each walk produces a byte mask and the youngest queued value
for each selected byte. Those results are then overlaid on the destination
words. Queue order, address comparisons, byte enables and all sequential
state are unchanged. No capacity, extra state or additional clock is added.

An isolated Quartus 17 synthesis of the 8 KB data cache reduces logic LUTs
from 1,752 to 1,474 and estimated ALMs from 1,711 to 1,573. Both versions use
568 registers and 74,624 block-memory bits. These are component synthesis
estimates; whole-core placement and routing determine the actual saving.

`tests/run-z486-store-forward.sh` exercises 21,233,664 combinations of queue
order, count, valid flags, matching/nonmatching addresses and every byte mask
against the retained independent per-slot reference inside the cache. It
checks both matching and different request/fill DWORDs. A missing-byte
mutation is rejected. This combinational check supplements real-CPU tests;
it does not replace FPGA and hardware qualification.

Local component reports and before/after sources are retained under
`build/store-forward-area/`. Whole-core qualification is still pending.

## Whole-core result

The 90 MHz PR2/32 KB instruction/8 KB data-cache candidate at source f7388d0
failed placement with seed 6: 41,730 ALMs, 551 M10Ks and 50 DSPs required
4,200 LABs, exceeding the device's 4,191. No RBF or hardware result was
produced. Its 84 CPU cases and 40 differential seeds passed; all 84 cycle,
instruction and active-cycle counts match the preceding early-grant version.

The isolated synthesis saving did not translate to a usable whole-core fit.
This implementation is preserved only on `memory-shared-forward-experiment`;
it was removed from the active `memory-early-grant` candidate. Evidence is in
`build/early-grant-shared/failed-fit.rpt`, `cycle-equivalence.json`, `full.log`
and `fuzz-verified.log`.
