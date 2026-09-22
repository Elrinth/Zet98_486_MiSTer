# GRCG comparison reads

With GRCG enabled in TDW mode (port 7Ch bits 7:6 = 10), a VRAM read compares
all enabled color planes at the addressed pixel offset with their tile bytes.
Each returned bit is one only if every participating plane matches. Mode bits
3:0 disable their respective B/R/G/E planes. With every plane disabled, the
result is FFFFh. The addressed plane does not select a tile for this operation.

The previous implementation requested one SDRAM word, then selected a tile
using the address's low bits. This could report a match despite a different
enabled color plane disagreeing. `Zet98/grcg.vhd` now requests READ4 for TDW
comparison, combines the four results and retains READ1/raw data for disabled
GRCG and RMW reads. Both the CPU and drawing instances use that implementation.
Mode writes also restart the tile register sequence at B after a partial load.

Primary reference behavior:

- [NP2kai TCRRD8/TCRRD16](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/mem/memvram.c)
- [MAME upd7220_grcg_r](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc9801_v.cpp)
- [MAME grcg_w](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc9801.cpp), including mode-write tile-index reset

Validation commands:

```sh
bash tests/run-grcg-compare.sh
bash tests/run-grcg-sdram.sh
bash tests/run-data-bus.sh
```

The comparison test uses per-pixel equality across enabled planes, independent
of the RTL XOR/AND expression. It covers every plane mask and addressed-plane
alias, isolated mismatches at every bit, changing words, partial tile loads,
held I/O strobes, select gating and raw reads, in both GRCG merge modes.
Negative controls break the comparison reduction, four-plane request, plane
disable mask and tile-index restart.

The integration test connects the actual GRCG to the actual SDRAM controller
on both CPU and drawing ports. It verifies SDRAM command addresses and the
result at acknowledgement, with distinct returned planes, multiple source
clock rates and phases. Its burst source is a command-level model, not an
electrical SDRAM model. FPGA timing and hardware captures remain separate
requirements; simulations alone do not establish either.

The old bus regression's single-plane expectation was corrected; keeping that
expectation would preserve the hardware bug.

`tests/hardware/grcg_compare_probe.asm` creates a DOS capture of 2,048 records:
two pages, every plane-disable mask, all four addressed-plane aliases and
sixteen pixel offsets. Each record contains aligned/odd word reads and both
byte reads. `scripts/verify_grcg_compare_probe.py` checks 12,288 result bytes
against per-pixel color equality and rejects missing, reordered or malformed
records. Run the probe only on a disposable DOS test disk; it changes off-screen
VRAM, enables 16-color access and leaves GRCG disabled. A prepared diagnostic
is not a completed hardware test.

The FullFont50 baseline on SuperStation One produced a complete capture with
SHA-256 `ec02880d3cb93c8487e192334e132bc454bf72cb56156d464972b37c02e3322a`.
All 2,048 records disagree with the correct comparison. All 2,048 agree exactly
with the old one-plane implementation, including its address-selected tile
and ignored plane-disable mask. This confirms the diagnostic reaches the
faulty path; it does not verify the replacement FPGA implementation. Retesting
the same probe on a timing-qualified build remains required.

The identical DOS binary and initial floppy also pass all 2,048 records in
the NP2kai reference emulator: 12,288 compared bytes, zero mismatches, capture
SHA-256 `9d90c547d87fc1809b05764a7afefd0be16dee1c36b09b4de2b7127e364cb80a`.
This validates the capture/verifier pair against a separate implementation.
