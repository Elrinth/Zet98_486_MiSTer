# Scaler pixel sum and clamp

`poly_final` used a nineteen-bit modular sum of each pair of partial filter
results, then sign/clamp detection and selection of eight pixel bits. Build
#110 had a -0.276 ns cold-corner HDMI path through this operation.

`poly_bound` adds the seven discarded fractional bits independently and
computes both twelve-bit upper sums (with and without their carry). Each
upper sum is clamped before the low carry selects its eight-bit result.
The original modular wrap, negative clamp, positive saturation, truncation,
RGB wiring, and pipeline latency are unchanged.

`tests/prove-ascal-poly-bound.py --prepare build/ascal-poly-proof` extracts
the actual VHDL functions, verifies all RGB call sites, synthesizes them with
GHDL, and analyzes the full scaler. `--prove` uses Yosys to compare that
netlist against the original nineteen-bit arithmetic for every input pair.
Wrong fractional carry, lost carry increment, and lost sign-bit mutations
must fail. Preparation uses the mixed simulator image; proof uses the formal
image. Preserve and copy the generated directory between those runs.

This is an arithmetic equivalence check, not a timing verdict. A routed
all-corner build must establish whether the shorter sums improve HDMI timing.
