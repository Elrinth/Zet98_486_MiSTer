# Hunt title-menu hang: graphics rectangle completion

Investigation date: 2026-10-08. Baseline: B248, 75 MHz, latest OpenBIOS.

The requested final candidate is **90 MHz**. The 75 MHz results below are the
initial validation baseline; the same RTL is being rebuilt and must be checked
at 90 MHz before those results are attributed to that configuration.

## Cause

After Enter on Hunt's title screen, the StartUp bar appears but its dropdown
does not. The game is waiting for the graphics controller to finish drawing
the dropdown border. This is not a failure of the JAST mouse reset/probe:
INT 33h function 4 returns, keyboard release is processed, and the subsequent
graphics wait is where execution stops.

The `DM_RECT` implementation in `Zet98/GDC/gragdc.vhd` never decremented
`D_NUM`. A side longer than one pixel therefore could not finish. It also
updated its internal cursor without presenting the new address to VRAM.

The captured command has FIGS `40h`, dot 5, DC `0003h`, D `0026h`,
D2 `005Eh`, D1 `FFFFh`, DM `0026h`, and cursor address `1BB9h`:
a 38-by-94-pixel rectangle. At the stalled completion wait, status `ACh`
has FIFO-empty set and drawing-busy still set.

## Correction

The rectangle engine uses one read/modify/write sequence for all four sides.
Each acknowledged pixel write decrements the side count and advances the
cursor. The next read receives that updated address. Finishing a side rotates
the direction by two and alternates the D and D2 lengths. Zero-length sides
turn without writing. The controller waits for acknowledgement to fall before
starting the next transaction or completing the figure.

This is a general graphics-controller correction. It requires neither a game
patch nor a BIOS workaround.

## Verification

`tests/run-gdc-rect.sh` exercises the production graphics-controller RTL with
GHDL 4.1. It checks completion, exact pixel addresses, selected-pixel masks,
and paired reads/writes for all eight directions, pitches 40 and 160, and
dimensions 5x3, 1x1, 0x3, 0x0, and Hunt's 38x94 command. Acknowledgement
delays of 0, 2, and 9 cycles all pass (240 cases).

The released RTL fails the new regression with a non-terminating rectangle.
A negative control that removes the counter decrement from the corrected RTL
is also rejected. The existing `tests/run-gdc-pram.sh` suite passes all six
command-gap/acknowledgement combinations and its old-alias negative control.

On B248 hardware, a private diagnostic that clamps rectangle sides to one
pixel opens the previously missing dropdown. Merely bypassing the game's
wait to observe drawing start does not. These modified game images are
diagnostics only and are not distributed.

On MiSTer, the corrected 75 MHz candidate with the original Hunt A/B disks
and OpenBIOS opens the complete dropdown, accepts New Game, reaches player
selection, and enters the in-game board/map. The in-game roulette menu opens
and animates. No game executable or BIOS was patched in this run. This is a
boot/menu/early-gameplay check, not a full playthrough or audio qualification.

Private screenshots are retained under ignored `build/egc-dsp/`:
`Hunt-rectfix-dropdown.png`, `Hunt-rectfix-playerselect.png`,
`Hunt-rectfix-key-start.png`, `Hunt-rectfix-gameplay.png`, and
`Hunt-rectfix-roulette.png`.

The candidate uses the full B248 75 MHz build profile with Quartus Lite
17.0.2. Fitting succeeds with 41,414 ALMs, 4,191 LABs, 43,896 registers,
552 M10Ks, and 67 DSP blocks. Worst slack is -5.155 ns with four negative
checks: within the project's accepted 12 ns magnitude limit, but not timing
closure. The pixel global-clock and 64 FEC route-atom checks pass.

Candidate RBF SHA256:
`3e0b4558d9a8cc76ecde3fa539c02f7441ae860acb8b56ea48187e6578c7dd59`.
OpenBIOS SHA256:
`671acbafb4a7baf5ffb69d740ccfd4cf9dc94d840b2b7881a20bf595621fd4f2`.

The original Ce2 ROM also opens the formerly frozen dropdown and reaches
player selection on this candidate. In-game progression was not established
in that secondary run; only the OpenBIOS run is qualified through the map and
roulette. OpenBIOS was restored afterward and the candidate reloaded.

## Separate Eden no Kaori limitation

The two supplied Eden sets contain matching sector payloads. The loader
requests special sectors which are absent from these images, then
stops after disk validation in NP2kai too. The visible mouse-driver banner
alone does not identify a mouse-controller fault. This rectangle correction
does not establish that those Eden images will boot.
