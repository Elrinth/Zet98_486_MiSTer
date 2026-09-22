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
faulty path; it does not by itself verify the replacement FPGA implementation.

The identical DOS binary and initial floppy also pass all 2,048 records in
the NP2kai reference emulator: 12,288 compared bytes, zero mismatches, capture
SHA-256 `9d90c547d87fc1809b05764a7afefd0be16dee1c36b09b4de2b7127e364cb80a`.
This validates the capture/verifier pair against a separate implementation.

On 2026-09-22, the StatusReturn60 build passed the same probe on SuperStation
One: all 2,048 records and 12,288 bytes matched, with the same capture hash as
NP2kai. Evidence is in `build/hardware/status-return60-validation/`. The RBF
hash is `bbd75ac9ce8e1cfcbf4de13d15c04d650891d59f7bc4f1694ceab618f6b7e541`.
Its routed source is `5a5ea82`. Final timing was rerun on that unchanged routed
database after the return-data SDC guard was corrected to accept physical
register duplicates while checking every logical bit. All reported timing
checks passed, with minimum slack 0.066 ns. This verifies GRCG comparison
reads; it does not establish a Rusty frame rate or qualify later RTL edits.

## Four-plane write alignment

The mapped SDRAM address's low two bits select B/R/G/E. A four-plane RMW must
align both its read and write column to plane zero. The controller previously
aligned the read only, so accesses through R/G/E aliases could start writing
at a different column. Both CPU and drawing-port writes now align those bits;
the per-plane and per-byte masks still determine which words are stored.

`tests/run-rmw-plane-alignment.sh` exercises all addressed planes through the
actual SDRAMC at 20/60/100 MHz on both ports. Restoring either old write column
independently must fail. These six runs, the two negative controls, and existing
affine/request/write-bundle/read-bundle regressions passed in
`build/simulation-20260922-094803-c7949d/tests.log`. That combined job later
failed an experimental EGC test adapter, so its overall exit status is one.
The write-alignment change is newer than StatusReturn60 and still needs its
own FPGA build and hardware test.

`tests/hardware/grcg_alias_probe.asm` records RMW writes through each B/R/G/E
address alias, on both pages and with all sixteen plane-disable masks. Its
512 records include aligned words, both byte lanes and odd words, surrounded
by unchanged guard bytes. `scripts/verify_grcg_alias_probe.py` checks all
16,384 bytes using a per-pixel set/preserve model. The probe writes exclusively
to a new `Z98GAL.BIN`; use a disposable DOS floppy with at least 64 KiB allocated
to the COM program. It enables 16-color access, changes eight off-screen bytes
per plane/page, restores the CPU page and leaves GRCG disabled. Run
`bash tests/run-grcg-alias.sh` to assemble the normal and shell versions and
check the capture verifier. Hardware execution is a separate step.

The first SuperStation capture, on StatusReturn60, failed 360 of 512 records
with 1,688 incorrect bytes. All 128 B-addressed records passed; each of R/G/E
failed 120 records (its eight all-planes-disabled records were unaffected).
All 512 records exactly match a model of the old burst column rotating each
plane's result and write mask by the addressed alias. This establishes that
the hardware probe reaches the faulty path. The capture SHA-256 is
`4a9837a0b905567d4d0a5885c837cf195978c3de645fd368e9990b6d891cd6dc`;
private evidence is in `build/hardware/grcg-alias-validation/`.

The first PlaneAligned60 compile (`quartus-20260922-101028-235b48`, source
`c3f36f3`) completed successfully but initially reported a -0.018 ns fast/cold
hold check on the held GDC configuration snapshot. After validating that
handshake's source hold interval, only its impossible nominal-edge hold check
was excluded; its 20 ns setup bound remains. TimeQuest on the same routed
database passed all four corners with minimum slack 0.061 ns. An additional
check found all 111 bounded GDC payload setup paths at every corner. The
unchanged RBF hash is
`80f216b7ffe99ae2c3660217a0fe9a8e62e5f752d47a04d5ccf1c69f3ac7e65c`.
Reports and the overlaid constraint are retained under `timing-gdc-hold/` and
`gdc-hold-qualified.sdc` in that build directory.

PlaneAligned60 then passed all 512 hardware records and 16,384 compared bytes,
including both pages, every addressed alias, plane mask, byte lane and odd word.
Its capture SHA-256 is
`e98ceaf0dc69d57b69f9f7146cfbcfc96b9292ec7dae418660d16c7f275c6960`.
The result was extracted only after unloading the core and confirming the
floppy was closed. The corrected capture screenshot showed only `NEC` despite
the complete result file: display behavior remains a separate open issue, so
this memory diagnostic does not qualify the build's overall game behavior.
