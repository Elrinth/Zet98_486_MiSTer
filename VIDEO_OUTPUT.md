# PC-98 display options

The core exposes the actual 640x400 picture to MiSTer's HDMI scaler. The
previous 640x480 capture included 80 permanently black lines above it.
Changing capture DE does not change native RGB, pixel frequency or sync.
Color bars retain their separate 640x480 diagnostic raster.

`HDMI scaling` now defaults to **Fit native**: preserve the measured source
pixel aspect and fit the whole picture into the output. At 1920x1080, the
normal 640x400 source occupies **1728x1080** (2.7x on both axes).

Other menu choices are:
- **Integer fit**: largest equal whole-number multiplier that fits completely.
  The normal 1080p result is **1280x800**, with borders and exact 2x2 pixels.
- **Integer zoom**: next whole-number multiplier, with a centered crop where
  necessary. At 1080p, 640x400 becomes 1920x1200 at 3x; the middle **1920x1080**
  is displayed. This removes 20 source rows (60 output rows) at each edge.
  Game HUD/text at those edges may be lost. The loading indicator moves inside
  the retained rectangle so its caption remains visible.
- **Stretch**: fill the entire HDMI viewport, changing the picture's proportions.
- **CRT 4:3**: fit to the traditional display shape, independently of pixel aspect.
- **Custom aspect**: use the separate existing Aspect ratio menu.

Native fit avoids aspect distortion but fractional nearest-neighbor scaling
still produces unequal pixel widths/heights; use Integer fit or Integer zoom
for uniform replicated pixels. Interpolation/filtering is controlled by the
MiSTer video preset. No scaler filter or global HDMI/HDR setting is changed.
`video_mode=8` selects 1080p60. The test machine has a scoped `[Zet98_Test]`
1080p profile; other cores retain their existing output settings.

The helper measures the actual core raster, not a game's advertised internal
resolution. This core currently emits 640x400 (640x480 for diagnostic bars).
If a future video mode genuinely emits 320x200, integer fit at 1080p is 1600x1000
at 5x; 320x240 is 1280x960 at 4x. These input sizes are simulated, not claimed
as new hardware video modes. Repeated/doubled pixels are not automatically
removed, since doing so could discard text or mixed-resolution graphics.

The MiSTer interface uses 13-bit aspect outputs; bit 12 marks explicit viewport
dimensions. Crop is a DE mask only at the HDMI scaler's final capture input.
Native RGB, sync, CE and analogue DE remain intact. A crop rectangle is latched
at vertical sync; integer math uses sequential addition/subtraction rather than
a combinational divider. Source modes larger than the output safely fall back
to fractional native fit.

`tests/run-video-scale.sh` verifies 720p/1080p/1440p, 400/480-line and 320x200/
320x240 source measurements, crop pixel coordinates, CE stalls, exact-fit cases,
mode changes and small-output fallback. The previous V-Integer mode's
1066x800 viewport was measured on hardware, but it intentionally changed the
640:400 source proportions to 4:3. It is no longer the default. Native50 fits
with no negative reported timing slack. Hardware scaler metadata confirms
640x400 to 1728x1080 for Fit native and 640x400 to 1280x800 for Integer fit.
These metadata readings are not measurements of the physical HDMI transport.
Integer zoom also reports a 640x360 capture into 1920x1080, matching a 3x
integer scale with 20 source rows cropped from each end of the 400-row image.
Fit native was restored after these checks.

## Analogue output

SuperStation One supports simultaneous digital/analogue output, but this
core's native raster is currently 800x525 at 25 MHz: 31.25 kHz horizontal and
about 59.52 Hz vertical. Its RGB picture is 640x400. It is suitable for a
compatible VGA/multisync monitor, not a normal 15 kHz SCART television.

A SCART cable alone does not convert that timing. Full-detail RGB-TV output
needs a separate approximately 15 kHz interlaced scan converter; progressive
200/240-line output would discard or combine source lines. Neither path is
implemented or hardware verified yet. HDMI integer scaling does not provide
this conversion, and `vga_scaler=1` with 1080p selected is not a SCART mode.

References:
- [SuperStation One specifications](https://retroremake.co/pages/superstation%E1%B5%92%E2%81%BF%E1%B5%89)
- [MiSTer video scaling](https://mister-devel.github.io/MkDocs_MiSTer/advanced/videoscaling/)
- [MiSTer video configuration](https://mister-devel.github.io/MkDocs_MiSTer/basics/video/)

## Activity overlay

The optional indicator remains on by default. It displays the supplied
rotating disk above `Loading D0` or `Loading D1` and zero through three dots.
FDC-selected drive activity is combined with each drive's HPS transfers.
If both request service together, the last uniquely active drive is retained.
It expires after 15 idle frames. It never draws into blanking; RGB, DE, sync
and clock enable have the same three-clock pipeline latency. A tile-map lookup followed by a shared
pixel-tile lookup reduces animation storage without dropping any frames.
Crop validation and indicator bounds are calculated in three register stages
starting at vertical sync. This removes crop arithmetic from the caption's
per-pixel path and keeps indicator placement fixed during the visible frame.
ROM addressing uses only bounded local disk coordinates; the larger global
rectangle/enable test masks the final output without gating the ROM address.

## Graphics scanout correction

The graphics row counter now advances toward the first partition boundary,
checks that boundary only after completing a logical row, and preserves all
ten GDC length bits. Previously it counted down from zero and could not reach
a normal positive split position within the visible picture. Repeated raster
lines reuse the line buffer. Vertical blank no longer issues graphics reads.
For a 400-row picture without repetition this removes 125 of 525 line fetches
per frame, about 24% of graphics fetches; it is not a measured CPU-speed gain.

Only the two existing starting-address windows are exposed. The second window
continues to the bottom of the screen; additional parameter-RAM partitions,
wrapping through drawing-pattern RAM, and display zoom remain unsupported.
Graphics and text GDC settings are registered before pixel-domain address
arithmetic, with their clock crossings still timed. CRTC98 first stages these
settings on the 75 MHz parent clock: direct CPU-to-pixel transfers required
hold-fixing route delay for one divider phase that then missed setup in another.
This adds one parent-clock cycle to settings updates without retiming the raster,
pixel data or palette. The parent-clock fit passes CPU-to-pixel setup/hold
checks. Its unconditional settings registers now update during reset as well;
the pixel reset still holds consumers for two pixel-clock edges before use.
This removes unnecessary reset fanout from the parent pipeline.
VTIMING now delivers its
counters directly to pixel-clocked consumers, removing the previous
pixel-to-75-MHz-to-pixel round trip. The sampled raster coordinates and
line/frame pulses are unchanged. Full-frame counter checks, text rendering,
SDRAM transfer checks, text-row alignment, retrace interrupts and 40 reset
release phases pass simulation.

The full FPGA fit confirms the corrected quoted QSF destination uses a global
clock network; the build script rejects a missing assignment. Global routing
alone did not close timing: it exposed the counter round trip and text-address
paths addressed above. Native50 now passes the reported timing checks, but
SDRAM/HDMI board-I/O constraints remain incomplete. Hardware diagnostic text
and Rusty's title screen render coherently; sustained gameplay and physical
output stability still need testing.

`tests/run-graphics-address.sh` checks both complete frames at split lengths
1, 3, 200, 400, 513, 1023 and zero, repeat counts 0/1/3/31, 14-bit VRAM wrap,
and zero fetches during blanking. The original code fails at row 3 in the
three-row split case. Partition semantics were checked against NEC's
[uPD7220/7220A user manual](https://www.bitsavers.org/components/nec/uPD7220/uPD7220-uPD7220A_User_Manual_Dec85.pdf),
section 4 (PRAM), and the NP2kai scanout reference. Zero does not switch within
the supported 400-line raster; behavior after 1024 logical rows is not tested.

## Palette staging after the 60 MHz decode fit

The 5bab734 fit exposes a -1.007 ns CPU palette-register to video-output
setup path. An opt-in grpal setting now stages the 16-color bank, eight-color
bank and color mode on the existing 75 MHz video clock before palette lookup.
CPU palette programming/readback and the pixel/sync pipeline are unchanged;
palette changes gain one video-clock update delay. The legacy generic keeps
the original unstaged behavior for other integrations.

The unchanged upstream palette is the simulation reference. Six CPU rates
and three video phases pass random palette writes/reads, color-mode changes,
mid-run reset and all pixel indices. Outputs are checked at the video edge
and between edges; CPU readback is checked independently. Deliberately using
the live CPU bank fails the between-edge check. Complete FPGA timing and
hardware validation of this palette change are pending.

## OSD configuration timing

The 5bab734 60 MHz fit also reports a -0.534 ns hold violation from
OSD infoh to its video-domain horizontal counter. Menu enable, geometry,
rotation and info-mode settings now pass through two video-clock registers
before coordinate arithmetic. Pixel, sync and OSD-buffer pipelines are
unchanged. All crossings retain normal setup/hold checks; there is no new
false path or claim of an asynchronous multi-bit handshake.

`tests/run-osd-video.sh` compares against the unchanged original menu with
CPU writes through its real command interface. Eight configurations cover
info mode, ordinary menus, all four rotations, disable and 320x200/640x400
rasters at 50 and 60 MHz CPU clocks. It checks 3,411,200 pixel/sync results,
requires actual overlay pixels in enabled cases and checks every settings
pipeline update. A deliberately bypassed stage fails. Because the inherited
OSD lacks reset for some registers, both simulation models explicitly use
zero-initialized two-state registers; this does not test analog power-up
behavior or metastability. `tests/Dockerfile.video` provides Verilator for
fast full-frame runs, with an Icarus fallback. Full FPGA timing and hardware
validation of the OSD change are pending.

## Graphics line-buffer input hold

The palette-stage 60 MHz fit exposes a -0.254 ns hold path from SDRAM
video data to the graphics line-buffer RAM. GRAPHSCR98 now captures all
four completed plane words on the existing GRAMACK edge, before the
following pixel edge writes them into the line buffer. The existing BUFWE,
write address, request/ACK sequence and raster pipeline are unchanged.
No new timing exception is introduced.

The real SDRAM controller and graphics module pass 16 four-plane lines
at six relative clock phases with a 20 ns injected data route; a 200 ns
late-data negative fails. Two-frame address tests pass split lengths
0/1/3/200/400/513/1023, repeat counts 0/1/3/31, 14-bit wrap and no blanking
fetches. The tested source hash was checked against the workspace after
correcting an initial Docker copy that used the previous source. FPGA
fitting and hardware validation of this capture stage remain pending.
