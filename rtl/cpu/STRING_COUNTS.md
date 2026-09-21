# Registered repeated-string count predicates

The GlobalLimits60 fit (source 78318fc) reports a -0.937 ns slow/cold path
from ECX through repeated-string completion, write-debug preparation and
pipeline readiness into instruction decode. `write_register.v` now keeps
four derived bits beside ECX: whether CX/ECX is zero or one. They update on
the same edge from the same selected next value, including reset and partial
CL/CH/CX writes. `write_string.v` consumes those bits for REP ignore/finish.
No architectural register, instruction cycle or memory interface changes.

`python3 tests/prove-ecx-count-flags.py` proves the actual register module's
flags match ECX after reset for arbitrary inputs, including subsequent
resets and all write paths. Separate negative controls use the previous ECX,
omit reset, or ignore the high word; each produces a counterexample.
The test then compares all eight outputs of the actual string unit with
the preserved original module for arbitrary operands, segment state, REP
prefixes and address/operand sizes. A wrong 32-bit predicate is rejected.
A simulation assertion checks flag/register alignment on every CPU edge.

`CPU_REP_COUNTS=1 bash tests/run-cpu.sh` adds real-CPU cases to the standard
smoke program: zero-count REP with a nonzero high word, partial CL/CH writes,
32-bit counts 10000h/10001h across the low-word boundary, and zero/one-count
32-bit stores. Repeat with `LOWMEM_CACHE=1`. The optional assembly block
leaves the default smoke workload unchanged.

The formal and full-CPU checks pass. Standard cached/uncached smoke workloads
retain 576 bus transfers. The new REP cases pass with 759/751 transfers
without/with the low-memory data cache. Upper-cache loop measurements remain
218,562/5,470 cycles with upper instruction caching off/on; alias, DMA and
mapping negative controls still fail as expected. Lower cached ALU/VRAM/stack
counts remain 6,392/3,720/5,268 cycles. Protected-mode tests and the DOS RAM
probe's return to real mode pass with both 16 MB and 64 MB, including the
oversized-memory negative control.

Physical fitting is pending; this change is a timing candidate, not a
demonstrated clock-speed increase.
The independently running UpperCache50 fit uses source 0939a06 and does not
contain this count-predecode change.
