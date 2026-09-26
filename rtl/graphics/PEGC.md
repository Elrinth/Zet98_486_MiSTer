# PC-9821 packed graphics work

Status: **CPU routing, framebuffer DDR arbitration, RGB888 palette, GDC raster
and CRTC compositing are integrated and simulation-tested. B151 passes the
experimental timing gates and CPU/RAM/FM/OPNA hardware regressions. Packed
graphics and actual Doom gameplay are still undergoing hardware qualification.**

The selected Doom `pc9821.drv` requires a 512 KB byte-addressed framebuffer at
physical `00F00000h`, 256 palette entries and extended-mode controls. The B149
legacy path has a 16-entry palette and discards accesses to that framebuffer.
The separately observed SETUP-launch `alloca` error is still unresolved.

## Implemented and tested in isolation

`pc98_pegc_control.sv` provides CPU-clock register and address decoding:

- 6Ah extended-mode enable/disable after 07h unlock, and 68h/69h page selection.
- 09A0h status-index readback, using the existing GDC's display/analog/clock flags.
- A8h eight-bit palette index, AAh/ ACh/ AEh full-byte green/red/blue write events.
- E0004h/E0006h 32 KB window banks; E0100h packed/planar selection;
  E0102h linear-memory enable.
- Both 512 KB linear aliases (`00F00000h` and `FFF00000h`) and packed windows
  A8000h/B0000h, all mapping to the same 18-bit word offset.
- Explicit rejection of unimplemented planar window access and the unused
  B8000h window. These must not leak through to the old four-plane VRAM.

The linear-memory enable is independent of the display-mode latch and window
format. MMIO and banked windows switch with extended display mode. Accepted
write strobes must be one beat; decoding does not acknowledge RAM transactions.
These interfaces are memory-only or I/O-only as named; the integrating CPU
router must distinguish memory from I/O before using their selects.

`pc98_pegc_palette.sv` uses three 256x8 RAM banks. CPU and video reads are
synchronous on their own clocks. Configuration initializes black; guest reset
preserves palette RAM while mode control returns to legacy display. Mixed-port
read/write of the same entry permits hardware-defined old/new data. Different
entries are independent. Video compositing must account for its one-clock read
latency, including text, blanking and sync alignment. This RAM interface is not
a combinational CPU-to-pixel bus or a giant register snapshot.

Tests: `run-pegc-control.sh` enumerates the entire framebuffer through both
linear aliases and every bank of both windows, checks register lane/boundary
behavior, and rejects a four-bit palette index. `run-pegc-palette.sh` verifies
every RGB entry and component, CPU readback, simultaneous independent accesses,
video clock alignment and a truncated-index negative at four CPU rates and
three clock phases. `pegc_palette_synthesis.qsf` is a standalone Quartus RAM
inference check, not a core build.

2026-09-24 evidence: control simulation `155458-1ec88e` passed 2,098,729
checks and its negative. Palette simulation `155744-06c603` passed 3,840
checks in each of 12 clock combinations plus its negative. Quartus 17 analysis
and synthesis inferred three true-dual-port M10K RAMs (6,144 payload bits),
zero fabric registers and four logic cells. Its sole warning was the deliberate
single-processor setting. These are synthesis counts, not a full-core fit or
timing result. The complete standalone database (69 entries) is archived under
`build/hardware/pegc-development/palette-synthesis/complete-project`.

`pc98_pegc_memory.sv` bridges CPU halfwords and byte masks to exactly
`30F00000h..30F7FFFFh` in the core-owned DDR region. No framebuffer cache is
used. Both linear aliases and banked windows share this backing. Accepted DDR
reads drain across reset or canceled CPU requests, without completing a later
request with stale data.

`pc98_pegc_ddr_arbiter.sv` arbitrates ordinary CPU RAM, CPU framebuffer and
read-only video in the CPU clock domain. Grants remain stable under backpressure;
read ownership remains until every burst beat returns, including through reset.
Video bursts are bounded to 16 words and cannot cross the 512 KB backing boundary.
Round-robin selection prevents either CPU client from starving the line reader.

`pc98_pegc_line_fetch.sv` stores two 640-byte rows in a 2 KB dual-clock buffer.
A held address/bank request travels through a toggle/ack handshake. Only a complete
line received before its active pixels may become visible. An underrun blanks the
whole row, and a completion arriving in a later row cannot publish stale data.
The read pipeline has two pixel registers; palette lookup adds one more. Request
payload is now18 bits including page wrap. Its timing file bounds maximum and
minimum delay and excludes only the two first-stage toggle synchronizers.

`pc98_pegc_bus.sv` combines register decoding, palette and framebuffer transactions.
It distinguishes memory from I/O, snoops legacy port 6Ah only on completion, and
performs a register/palette write once even under a held ACK. CPU-only reset cancels
requests while preserving graphics registers. The optional `PEGC_ENABLE` branch in
`pc98_ao486.sv` gives this target priority over legacy VRAM and extended RAM, then
shares DDR through the arbiter. The top connects the real text-GDC flags, pixel
palette and video DDR interface. `scripts/build.ps1 -PackedGraphics` enables it
and the matching timing constraints; the default build keeps it disabled.

Additional 2026-09-24 evidence:

- DDR arbitration: `161315-c86726`, three seeds, 898 commands and 1,335 returns
  each, including byte writes, reset draining and an invalid-owner negative.
- Line reader: `162518-9ce2b3`, 90/100 MHz and three pixel phases under continuous
  competing CPU traffic. Uses the actual 160-pixel leading blank (6.36 us), tests
  wrap, forced multi-row stalls, stopped-clock reset, delayed payload and rejected
  stale/late controls. This is a modeled DDR service test, not a hardware latency
  guarantee. It supersedes the earlier 200-pixel-blank controls.
- Standalone Quartus 17 line synthesis: 16,384 payload bits in simple-dual-port
  M10K storage, 84 registers, 181 logic cells. Complete 57-entry project/database
  archived in `line-synthesis/complete-project`. No full-core fit/timing result.
- Bus target: `163019-65bfa2`, 13,738 checks, 326 DDR commands, exactly 768 palette
  writes, and repeated-side-effect negative rejected.
- Actual z486 CPU: `163451-f84dfb`, all 256 RGB palette entries, both linear aliases,
  16 banks, odd dword/byte writes, reserved-region and ordinary-RAM isolation.
  The existing 80-case protected-stack test also passed with the new arbiter enabled.
- Default route regression: `163700-dedc50`, CPU smoke/interrupt/IRET/reset,
  varied stalls and speed selections, cache/self-modification/DMA invalidation,
  64 MB RAM and debug-UART tests passed with PEGC disabled. Simulation speed-mode
  checks do not override the previously observed 60/30 MHz hardware stalls.

## Raster and full display integration

`VIDEO/pegc_raster.vhd` generates the 640x400 packed display. Start addresses use
SAD*16 bytes; pitch uses GDC pitch*8 at5MHz or *16 at2.5MHz, with word alignment.
The effective fast-clock flag requires both GDC clock-select latches, matching
NP2kai's clock calculation. Two-page mode wraps within the selected256KB page;
single-page mode uses512KB. Two partitions are implemented. Packed scanout
advances every output row and ignores the legacy GDC CSRFORM repetition count,
matching NP2kai `makegrex.c` and MAME `pc9821_state::screen_update`.
Other packed resolutions and planar drawing are not implemented or advertised
as qualified. The alternative MAME IM-based pitch expression is labeled a guess
in its source; these modes still need hardware comparison.

Six fields extend the coherent GDC snapshot to128 bits: high SAD bits for both
partitions, packed mode, single-page mode, display page and effective GDC clock.
They retain the parent rising/falling stages and pixel registers. Both partition
lengths now reach the packed raster. Field mapping, transport and endpoint guards
were updated together. The line RAM's two stages plus the palette's one stage
and six additional RGB stages align packed pixels with existing text and sync.
Legacy text/semigraphics overlays use the original renderer and palette.

Simulation `170151-e7b5b2` passed12,800 reference rows, both page-wrap modes,
90/100MHz line-fetch contention, exact640-pixel RGB888 alignment and text overlay,
reset/semigraphics regressions, and128-bit settings transport/mapping. Wrong SAD
units, stale publication, late payload, shifted RGB and broken snapshot controls
were rejected. An earlier test exposed and corrected a page-bit indexing error
in the new wrap logic; its failing log is retained.

Simulation `170615-0dd44d` connects the actual bus target, DDR arbiter, line RAM
and palette. CPU byte writes through both linear aliases produce3,840 checked
pixels at each of two clock/phase combinations, including page wraps and writes
concurrent with display. Truncating the palette index to four bits fails. This
models CPU bus transactions and DDR service; the separately passed z486 probe
checks the CPU instruction/bridge route.

The full candidate still must fit and satisfy setup >= -12ns and nonnegative
hold/recovery/removal. Export its complete Quartus database before removal.
Then qualify diagnostics, the displayed graphics path and original Doom on
MiSTer. Simulations do not resolve the separate SETUP-launch allocation error.

B150's worst setup path (-13.659 ns) launched in the pixel reset domain and
ended at CPU-side line-fetch/memory controls. Its worst recovery (-10.414 ns)
was CPU reset reaching pixel-register clears. The CPU-only setup was -7.285 ns.
The replacement uses separate two-stage reset-release chains in the CPU and
pixel domains: asynchronous assertion, release after two local clock edges.
Only those chains' asynchronous inputs are excluded from timing; their internal
stages, released-reset fanout, and all existing payload checks remain timed.
Simulation `181918-553017` passes six clock/phase line-fetch cases, stopped-clock
reset, accepted-memory-transfer reset and the integrated 3,840-pixel display at
two clock combinations. Restoring direct raw reset release is rejected.

B151 fits with 41,274/41,910 ALMs, 515/553 M10Ks and 61 DSPs. Its setup is
-7.052 ns; hold +0.101, recovery +1.095 and removal +0.254 ns. This meets the
user's experimental -12 ns setup allowance, not full static timing closure.
The complete Quartus database is archived. On MiSTer, CPU ALU/memory/stack,
64 MB physical RAM, FM timer/interrupt and OPNA detection tests passed, with
complete integrity audits of their result disks. These legacy regressions do
not by themselves establish correctness of the newly added packed display.
Original Doom direct launch subsequently produced red vertical stripes with
all 400 screenshot rows identical. ESC and F10/Y produced no visible change;
this is neither demonstrated gameplay nor proof of a CPU hang. The earlier
SETUP-launch allocation error remains a separate observation.

A self-authored DOS hardware probe fills and reads back all 262,144 bytes through
the bank windows, programs an RGB888 palette and explicitly sets a 640-byte
pitch, start address zero and a 400-line partition. B151 passes the readback.
The unobscured screenshot rectangle x=0..639, y=144..383 matches the independent
reference exactly: 153,600 pixels with zero differences. DOS text obscures the
rest, so this is not a whole-frame comparison. The saved result passes a complete
D88 integrity audit. An unmodified Popful intro control also displays correctly.
These results narrow investigation toward the BIOS/driver initialization state;
they do not yet identify which register differs during Doom or fix the game.

The extended-BIOS control reproduces a repeated first row despite correct
framebuffer readback. Adding pitch40 alone does not repair it. In a staged
hardware control, pitch40 and repeat0 still repeat the row; replacing PRAM
bytes0..7 with start0 and a400-line first partition restores the reference
pattern (71,680 unobscured pixels match exactly). Clock and display-enable
overrides afterward make no visible difference. This isolates the controller's
partition setup as the next investigation; it is not proof that all Doom faults
are solved. All four disposable probe result disks have full integrity audits.

## Graphics parameter RAM correction (hardware qualification pending)

The production GDC decoder previously treated a continuous PRAM write beginning
at70h as two aliases of the display registers: its ninth byte overwrote display
base0 instead of pattern byte0. A baseline simulation of the original decoder
reproduces the overwrite after modelling only the FPGA zero power-up value of
its otherwise uninitialized FIFO read pointer. The first eight bytes pass.

The corrected decoder uses all16 PRAM addresses and ignores excess bytes after
address15 until another command. MAME's upd7220 PRAM handler and NP2kai's command
length table agree on this bounded behavior. An earlier proposed wraparound
expectation was rejected after checking those references. The ordinary streaming
WDAT parameter counter retains its four-bit wrap independently. Hardware reset
now initializes the FIFO read pointer and decoder controls explicitly.

Actual production VHDL tests cover all16 starting addresses,512 streamed writes,
excess parameters,272 one-pixel pattern draws observed on the VRAM bus, and a
second hardware reset, at two host-write spacings and three memory ACK delays.
A16-byte partition/pattern sequence that would have produced repeated rows now
feeds400 distinct addresses to the actual packed raster. Restoring the old alias
fails. Existing raster and128-bit coherent settings transport tests also pass.
No new hardware success is claimed; the BIOS-only pattern and original Doom
must be rerun on the qualified candidate. The separate software GDC RESET
priority and11-bit packed partition-length gaps remain unchanged.

## Behavioral references

These are references, not copied implementation code. No game code/assets are
included in these modules or tests.

- [SL9821 author's PEGC analysis](https://www.satotomi.com/sl9821/sl9821_tec5.html):
  512 KB memory, RGB888 palette, bank windows and packed/planar/linear controls.
- [MAME pc9821.cpp](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc9821.cpp):
  memory aliases, mode registers and GDC-derived packed scanout. Its 256-color
  palette reads are unimplemented, so they are not used to define readback.
- [NP2kai gdc.c](https://github.com/AZO234/NP2kai/blob/master/io/gdc.c):
  protected extended-mode writes.
- [NP2kai memvga.c](https://github.com/AZO234/NP2kai/blob/master/mem/memvga.c):
  linear aperture enable independent of packed/planar window access.
- [NP2kai makegrex.c](https://github.com/AZO234/NP2kai/blob/master/vram/makegrex.c)
  and [pccore.c](https://github.com/AZO234/NP2kai/blob/master/pccore.c): packed
  start/pitch/page wrapping and effective GDC clock selection.

Primary sources were inspected on 2026-09-24. The particular driver's GDC scroll
sequence and display still require hardware qualification.

2026-09-24 B153 hardware clarification: corrected PRAM addressing removes the
one-row-across-the-screen failure. Banked readback passes 262,144 bytes and
original Doom displays its title, but the image is vertically cropped and
menu/gameplay response is unproven. The BIOS-only probe requests BH=11h, leaving
legacy CSRFORM=1; packed output must bypass this repetition according to both
rendering references above. Simulation232606-699bb8 reproduced the incorrect
B153 repetition. Simulation232742-bf75ad passes12,800 independent rows across
all32 CSRFORM values and actual GRAGDC CSRFORM1-to-raster integration, rejecting
the old behavior. The B154 candidate changes only this packed-raster behavior;
legacy display logic and the coherent settings interface stay byte-identical.
NP2kai's final `scrndraw.c` compositor also exits the legacy 200-line/double-scan
selection when `gdc.analog & 2` selects packed graphics. Thus the packed row
advance is not undone by a later legacy double-scan stage in that reference.
