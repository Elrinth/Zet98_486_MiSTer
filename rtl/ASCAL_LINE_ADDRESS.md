# HDMI line-buffer address carry selection

The FullFont60 fit at 4790ba7 had a -0.014 ns slow/cold setup path from
`ascal.o_hcpt[4]` through the line-buffer subtraction and bank mux to
`o_radl0[10]` at the 148.5 MHz HDMI output clock.

`ascal_line_address.vhd` computes both possible upper-six-bit subtraction
results in parallel, then chooses using the low-six-bit borrow. It retains
the original one enabled cycle of address latency, line-bank rotation and
modulo-OHRES wraparound. Quartus `keep` attributes preserve the independent
upper results. No scaler pixel/sync stages or clock-enable conditions move.
The previously registered `o_v_hmin_adj` stays in its original process.

`tests/prove-ascal-line-address.py` extracts the actual new instance wiring
from `MiSTer/sys/ascal.vhd`, synthesizes it with GHDL, and proves the resulting
register outputs against ordinary modular subtraction and the original bank
rotation using Yosys induction. It proves all 4,096 horizontal positions,
all independent current/delayed origins, all banks/fractions and arbitrary
clock-enable stalls for every power-of-two OHRES from 1 through 4,096.
Wrong borrow selection, incorrect bank routing and an ignored clock enable
each produce the expected counterexample. Full `ascal.vhd` analysis also
passes with its new dependency.

An initial zero-width OHRES=1 synthesis exposed a GHDL 4.1 assertion. Explicit
12-bit natural ranges for the address outputs/intermediates avoid that
tool bug; constant high result bits still optimize away. The final proof
includes OHRES=1 and passes for all 13 supported generic sizes.

The proof covers the changed address logic and its real instance wiring,
not every scaler filter/framebuffer mode. It establishes the same address
sequence without adding a cycle. An FPGA fit must still demonstrate the
timing improvement, followed by hardware video checks; no new verified
CPU frequency or Rusty frame-rate improvement is claimed from this proof.

Local evidence: `build/ascal-address-prepare-final.log`,
`build/ascal-address-proof.log` and per-case files under
`build/ascal-address-proof/`.
