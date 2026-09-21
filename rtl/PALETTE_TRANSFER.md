# Palette transfer between CPU and video clocks

The 60 MHz CPU and 75 MHz video clocks can have adjacent edges only 3.33 ns
apart. Directly copying the CPU palette on every video edge left negative
setup slack on PALREG/C8REG to PAL_VIDEO/C8_VIDEO in previous full-core fits.

The staged palette now copies the 192-bit analog bank, 24-bit digital bank
and color-mode bit into a held 217-bit snapshot. A request toggle passes
through two video-clock synchronizer stages. The following video edge copies
the complete snapshot and acknowledges it. Only after the acknowledgment has
crossed two CPU stages may the source reuse the held bank.

CPU reads and writes retain their existing behavior and latency. Writes or
mode changes during a transfer mark another snapshot dirty, including a write
on the same edge that launches a snapshot. Pixel lookup remains combinational
from video-clock registers; no pixel, blanking or sync pipeline stage is added.
Video reset asserts immediately and releases through a local synchronizer.

This introduces a bounded delay in visible palette programming. Several rapid
writes may coalesce into one snapshot; this is not a claim of cycle-exact
raster palette effects. Tests check the final bank/mode within one microsecond
at all supported simulation clock ratios. Hardware game compatibility and
physical timing are still pending.

`pc98-palette-transfer.sdc` bounds the held payload to 20 ns. The earliest
capture at 75 MHz is two full video periods after launch (26.66 ns), leaving
at least 6.66 ns to settle. Only the request and acknowledgment inputs to their
first synchronizer stages receive control false paths. Stage-to-stage paths,
CPU readback, video lookup and the remaining core remain normally timed.
The local reset exception ends only at the two synchronizer CLRN pins;
its data inputs and synchronized output retain normal timing checks.

`tests/run-grpal-video.sh` compares CPU readback against the original palette,
checks 1744 final pixel values per run, and monitors between-edge stability
during 6400 random bus cycles, both color modes and reset. It runs the actual
RTL and then adds 20 ns transport delay across all 20/40/50/60/90/100 MHz
ratios and three clock phases. A 60 ns payload delay must lose a final write
and fail; bypassing the video staging must fail its glitch check. The existing
CRTC compositor regression also passes. These tests do not establish that the
full core can run at those CPU frequencies.
