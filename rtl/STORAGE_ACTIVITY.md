# Compact storage activity display

The area campaign stays at **90 MHz**. The maintainer explicitly ruled out
further 100 MHz experiments on 2026-10-06.

`storage_activity.sv` restores the self-drawn floppy, CD and HDD icons in one
shared badge. It displays `LOADING D0...`, `LOADING D1...`, `WRITING D0...`,
`WRITING D1...`, `READING CD...`, `READING HDD...` or `WRITING HDD...`.
The Audio & Video menu's **Disk activity** switch controls the whole badge;
new status bit 49 avoids reusing bits now assigned to input controls.

The badge is anchored inside the HDMI crop when one is active, with 20 pixels
clear below it for the DOS function-key row. Background pixels stay transparent.
It uses the scaler's existing raster counters, one 8,192-bit ROM for the font
and four icon frames per device, and a frame counter for animation. RGB, sync,
blanking and CE pass through the same two-clock pipeline.

Independent request levels cross through two synchronizer stages. Pending
flags retain short requests until the next frame. The selected caption changes
only in vertical blank, and remains for 15 frames after activity stops. When
several devices request together, writes take priority, then floppy reads, CD
and HDD reads. A write caption keeps the existing hold timer when a subsequent
read or busy indication arrives, so a short write stays visible during readback.
Floppy writes combine the FDC's existing registered write gate with its
registered per-drive activity selection, as well as the image transport's
write request. The FDC keeps its busy/drive indication throughout the transfer
and result phases. The track cache deliberately delays
backing-file writes until three seconds after the guest stops writing, so the
transport signal alone cannot indicate the guest's save operation promptly.
The shared badge shows one device at a time. CD audio playback
uses the CD caption, as the earlier overlay did.

`tests/run-storage-activity.sh` checks all seven captions against the original
font, every retained icon frame against the original icon ROM, transparent
pixels, crop placement, idle/disable behavior, held short writes, priority and
continuous/bursty clock enables. `tests/run-video-scale.sh` also checks that the
shared raster coordinates match the incoming pixels through CE stalls.

The final two-stage badge maps to 227 combinational ALUTs, 123 registers and
one M10K (including the write hold). The previous overlay mapped to 617 ALUTs,
468 registers and three M10Ks.
These are component synthesis figures, not full-core ALM/LAB counts.

The EGC follow-up moves the common append mask into one additional DSP,
reducing the shifter from 670 to 631 ALUTs with its 171 registers unchanged.
Both multiplier operands are explicitly sixteen bits; otherwise Quartus
allocates two DSPs for the expression. The shifter now uses seventeen DSPs.

## Qualified combined 90 MHz build

Build `quartus-20261006-224455-6c0394` uses seed 2, PR2, IC32/DC8, 64 MB,
normal register packing and retiming, raw IDE, MIDI UART, packed graphics,
JT08 audio and the native-DDR framebuffer. It fits at **41,427 ALMs / 4,191
LABs**, with 43,267 registers, 552 M10Ks and 67 DSP blocks. Worst slack is
**-7.379 ns**; ten setup summaries remain negative. This is within the
maintainer's 12 ns allowance, not static timing closure. Pixel-clock,
HPS-peripheral and FEC route audits pass.

These combined totals are **47 ALMs above B245, with the same LAB count**.
The graphics optimization makes room for the restored display, but the
combined core does not establish a net area saving. The separately qualified
sixteen-DSP core without the display saved 231 ALMs and six LABs; see
[`graphics/EGC.md`](graphics/EGC.md). Component savings cannot simply be added
to full-core counts because placement and physical optimization change too.

RBF SHA256:
`0d8f6664ad9bf303cf00aa62e9989c6cac67ade15962823e519db0f21d8901a2`.

With the same OpenBIOS and media as the control, this exact RBF passes:

- Two fresh Linux boots, stack page-fault recovery and 100 traced normal
  process exits per boot.
- All seven storage-transfer modes and exact captured caption/icon pixels.
  Four intended floppy sectors change; all other sectors remain intact.
- 512 EGC alignments and 11,904 independent plane checks.
- DOS QUALIFY: four division rounds, 4,008 string cases, 531 KB conventional
  memory and 16 MB XMS, with zero errors.
- Complete EXTBENCH run: extended write/read/copy 26,818 / 20,969 / 13,967
  KB/s and conventional write/read/copy 30,122 / 7,270 / 6,433 KB/s.

The full Doom demo returns normally to DOS with **11,520 game ticks / 1,726
real ticks**, versus 1,724 real ticks in the reference runs. The observer
measures **723.52 seconds**, compared with 723.46 / 723.53 seconds for the
control, with three-second capture intervals. This shows essentially unchanged
performance, not a measurable speedup. The PC-98 counters are relative
benchmark values, not absolute FPS. The final capture and record are
`build/activity-area/CompactGateDoomEnd.png` and `CompactGateDoomResult.json`.

The renderer regression passes 4,026,630 pixel/sync checks, including writes
followed immediately by reads. `tests/run-disk-interface.sh` checks both guest
write indications through the real wrapper before any SD flush, rejects a
disconnected-gate mutation, and checks that reads or an unselected write gate
do not report writes. IDE, native HDI and MIDI wrapper checks also pass.

## Apple Club 1 release comparison (2026-10-07)

The reported B245 red-dot regression is reproducible on the Apple Club 1
title screen with OpenBIOS. B244 is clean on two fresh core loads. B245 has
the same 1,312 erroneous pixels on two fresh loads: only the red channel
changes, at horizontal positions congruent to 12 modulo 16. Separated
captures of each release are also stable.

The combined candidate identified above matches B244's entire 640x400 title
image pixel-for-pixel on three fresh loads. These comparisons use the same
disk copy, BIOS and settings, with a menu-core transition before every load.
The source archive and extracted D88 remain unchanged. Local evidence and
the pixel comparison are in `build/apple-club/results.json` and
`build/apple-club/pixel-results.json`; captures are under `build/egc-dsp/`.

This qualifies this candidate's title rendering, not complete gameplay or
the underlying cause. The B244-to-B245 source changes only alter gamepad
routing; the test does not establish why that release bitstream corrupts
the red plane or which candidate change removes the symptom.

## Known compatibility limits of the B246 release

The private friend-supplied DOS image tested on 2026-10-07 reboots when its
original Doom and Doom II executables use VEM486/VCPI. A minimal VEM486 boot
also reproduces the Doom reset on both this candidate and B245. With a clean
HIMEM-only boot, Doom reaches gameplay and returns to DOS normally, but Doom
II still fails during texture initialization or level loading. B245 also
shows texture errors, including with sound disabled. Host-side checks find
all referenced map textures and texture patches in the supplied WAD.

The failing CPU, memory, BIOS or physical timing path has not been isolated.
This release does not claim to fix those failures, the Windows 95/98 desktop
issue, or all game compatibility. The successful reference Doom timedemo
uses a different boot configuration. Private evidence remains under
`build/friend-doom/`; no game or DOS files are included in the release.

## Rejected fits

The three-stage display exceeded capacity. Disabling physical retiming fitted
at 39,430 ALMs / 4,174 LABs but stalled in DOS initialization. Two builds with
an extra registered two-bit write decoder passed DOS checks but panicked in
Linux: `quartus-20261006-205130-153182` and
`quartus-20261006-214736-42686b`. Their lower area figures are not accepted
savings. Control and intermediate builds passed fresh Linux checks using the
same BIOS, disk and core filename. The current scalar gate revision reuses
existing registered signals and has passed the Linux checks above. The
physical cause of the earlier failures is not established by this comparison.

Component and hardware evidence is kept under `build/activity-area/`, with
the mask synthesis comparisons under `build/egc-mask-area/` and
`build/egc-mask-narrow/`.
