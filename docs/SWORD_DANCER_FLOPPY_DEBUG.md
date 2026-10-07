# Sword Dancer floppy recognition investigation

Hardware investigation: 2026-10-07, B246 at 90 MHz, OpenBIOS 2026-10-06.

## Initial diagnostic result

The original game disks reached the in-game map on MiSTer with a private
diagnostic BIOS. This is evidence for two floppy BIOS/controller compatibility
problems, not a released fix. No game executable was patched in this successful
run, and the FPGA bitstream was unchanged.

1. OpenBIOS accepts a probe for an inactive floppy interface and switches to it.
2. The game's DOS does not receive the media-change status it needs to invalidate
   its cached disk information after a swap.

## Evidence

- The seven converted D88 sector payloads match their original FDI payloads.
  The same original FDI and converted D88 disks reach gameplay in NP2kai.
- A controlled B246/OpenBIOS run rejects Disk D in either drive. Disk D SHA256:
  `6face950c56c9b82270ee1cdf8c230700cb3d4f3f549b044ac1136fa4cc44739`.
- OpenBIOS `DEBUG_1B` tracing shows repeated `AX=7A70` and `AX=7A71` READ ID
  requests returning `AH=C0` (no data). These address the 640 KB interface.
- The game's `IO98.SYS` at file offset `18DAh` issues `AX=83F0h` to probe that
  interface. Its following carry test controls installation of its alternate
  floppy interrupt handler.
- OpenBIOS `fd_select_interface` unconditionally changes port BEh. In an isolated
  BIOS model test, this probe returns success, changes interface 1 to 0, and
  changes equipment word 055Ch from `0003h` to `3003h`.
- NP2kai `bios/bios1b.c:setfdcmode` rejects a request whose interface bit differs
  from `fdc.chgreg`. Rejecting the same probe in the private BIOS returns
  `AH=40h, CF=1` and preserves interface 1 and equipment word `0003h`.
- That diagnostic alone removes the repeated wrong-interface probes, but the
  game still does not load after acknowledging the Disk D prompt.
- `IO98.SYS` hooks INT 13h and examines the not-ready bit in the BIOS result
  records at 0564h + unit * 8. Its media-status routine consumes this state.
  The current OpenBIOS IRQ handler only sets completion flags and sends EOI;
  the core also lacks asynchronous ready-change notifications.
- A second diagnostic writes not-ready records for both drives and invokes the
  hooked INT 13h when the BIOS returns a blocking key read. With both diagnostics,
  acknowledging the correctly mounted Disk D with Enter triggers successful
  `7A90/7A91` READ ID calls and successful `5690/5691` reads, followed by the
  outdoor in-game map and HUD.

The synthetic key-triggered notification is deliberately a diagnostic. It must
not be shipped: pressing a key is not evidence that a disk changed. A proper fix
must report real mount/eject transitions, preserve pending seek/data completion
events, and update the BIOS result records before chained DOS IRQ handlers run.
Interface validation must also preserve explicit BIOS boot-time interface
selection and support for 2DD media.

## Private evidence and restoration

Evidence is under ignored `build/random10/sword-bios-debug/`, with screenshots in
`build/egc-dsp/`:

- `Sword-debug-D-settled.png`: failed probes and repeated Disk D prompt.
- `Sword-probe-D-result.png`: interface diagnostic alone, no gameplay.
- `Sword-cache-D-result.png`: successful map loading with both diagnostics.
- `Sword-diagnostic-gameplay.png`: follow-up input and scene capture.

The released BIOS file was restored after the diagnostic tests. Its SHA256 is
`d318ff406d5ab76d306e84c415ab82971b4b83b132758e15cfa6e692dd9021ce`.
The running session could retain the diagnostic ROM until the next core
load/reset that reloads the ROM. Those diagnostic experiments did not modify
production BIOS or RTL source.

An NEC UX BIOS comparison did not reach a usable game screen on this hardware;
it is not evidence for or against the disk-change diagnosis. NP2kai comparisons
also have a limitation: the emulator supplies BIOS/ITF behavior, so loading an
OpenBIOS ROM there does not validate its native floppy implementation.

## Production candidate

The subsequent implementation uses actual media-present transitions, with an
opt-in core register and an OpenBIOS IRQ handler. It contains no keyboard-triggered
notification and no game-specific patches. See `FLOPPY_MEDIA_EVENTS.md` for the
interface and compatibility limits.

The focused RTL test and all nine OpenBIOS test groups pass. Negative controls
also confirm the RTL test catches loss of the IRQ low interval after native
interrupts and acknowledgements. Existing floppy SDRAM tests pass at 20, 40, 50,
60 and 90 MHz, including their negative controls.

### MiSTer qualification, 2026-10-07

Candidate build `quartus-20261007-075958-dcaca1` at 90 MHz fits in 4,191 LABs
and uses 41,405 ALMs. Worst timing slack is -7.740 ns, within the project's
user-approved 12 ns negative-slack allowance; timing is not fully closed.

- Core RBF SHA256:
  `f5e389f2bde36a25444846259191b964979784fda7e68a74012ce852fb90ec05`.
- Paired OpenBIOS boot.rom SHA256:
  `4210f036d5dc6e2c4cdd83fccb210ba53059bd1aab0e349d84e216b67024bf0a`.
- Fresh floppy boot with A in drive 0 and B in drive 1: Initial Start requests
  D. Replacing B with D and acknowledging the prompt reaches the outdoor map.
  Further input reaches an indoor NPC conversation.
- Independent fresh boot: replacing A with D in drive 0 accepts D, then asks
  for A. Replacing B with A in drive 1 reaches the outdoor map with sprites.
- MS-DOS 6.20 on an isolated HDD: `HDINST` copies B into a fresh `SDGFIX`
  directory, then accepts A in the same floppy drive, completes its copy and
  requests C. The test stops at that prompt; full installation is not claimed.
  The released baseline previously rejected this correct A-disk swap.
- N88-BASIC smoke test: Zatsugaku Olympics boots, reaches the quiz and advances
  to another question after keyboard input on the same core/OpenBIOS pair.

All these tests use the original converted D88 images and the production
candidate, without diagnostic BIOS logging or keyboard-triggered notifications.
Private screenshots: `build/egc-dsp/Sword-events-gameplay.png`,
`Sword-events-D0-A1-result.png`, `Sword-events-install-A-accepted.png`,
`Sword-events-install-C-prompt.png` and `Zatsugaku-events-quiz.png`.
These exact binaries are selected for core B247 and OpenBIOS 2026-10-07.
