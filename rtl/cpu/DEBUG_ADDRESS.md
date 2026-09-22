# Breakpoint address comparison

The MaskGrcg60 fit at cdf93b9 misses slow/hot CPU timing by 0.070 ns on
`wr_eip -> write_debug -> rd_ready -> glob_param_1`. The instruction address
is first added to the CS base, then compared with four debug registers,
before breakpoint eligibility affects the pipeline's read-ready feedback.

`write_debug.v` now checks the addition equality using independent full-adder
equations. If `base + offset == breakpoint`, each breakpoint bit determines
the required incoming carry as `base XOR offset XOR breakpoint`. Each bit's
carry-out must match the following bit's required carry. That avoids a serial
32-bit carry chain before the equality comparison. Carry out of bit 31 is
discarded, preserving the original modulo-2^32 address calculation.

The low three bits retain all eight possible debug-length masks. A three-bit
addition computes those bits and the carry into bit three; the upper 29 bits
are always compared. The DR7 gates, instruction completion/limit checks,
exception priority, registers and clock cycles are unchanged.

`tests/prove-debug-address.py` extracts the actual function and all four
production trigger assignments. It asks Yosys to prove them equivalent to
the original masked addition/comparison for arbitrary bases, offsets,
breakpoint addresses, low masks and control inputs. Negative controls change
the low carry, carry propagation, low mask and upper-address comparison.
The proof and full CPU regressions must pass before this change is fitted.
A faster clock remains unproven until the complete core passes timing and
hardware testing.

The proof passed on 2026-09-22, including all four negative controls. The
saved log is `build/simulation-20260922-075145-e5ea9f/tests.log`. Uncached and
cached CPU smoke/REP tests, protected-mode 16/64 MB RAM access and real-mode
return also passed in the subsequent integrated regression. The cached
ALU/VRAM/stack workloads still take 6,392/3,720/5,268 cycles respectively;
these are simulation measurements, not Rusty frame rates or a higher
validated FPGA frequency.

The completed integrated regression is saved at
`build/simulation-20260922-075341-1cf1a7/tests.log`. All lower/upper-cache
coherence cases and their negative controls passed. Its eleven benchmark
signatures exactly match the preceding cdf93b9 regression, including
218,562/5,470 cycles for the upper-memory loop without/with caching. Both
proof and regression containers exited zero without an out-of-memory event
and were removed after their logs were saved.
