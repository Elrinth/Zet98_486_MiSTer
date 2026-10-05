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
