# GDC settings snapshot

At 60 MHz CPU / 75 MHz video, directly sampling the graphics pitch in the
video domain fails setup timing. The CRTC now receives all 19 programmed GDC
fields through a coherent 121-bit snapshot. The original port mapping is
recorded in `tests/reference/gdc_settings_fields.json`.

`video_settings_transfer.vhd` captures the settings on a CPU edge and holds
them until the video domain acknowledges receipt. A two-stage request
synchronizer precedes capture on the following video edge. A two-stage
acknowledgment synchronizer prevents early reuse of the source bank. Both
domains have local reset-release synchronizers. Snapshots refresh continuously;
intermediate CPU writes can coalesce, and visible settings acquire bounded
latency. This does not preserve exact raster programming timing.

The existing CRTC pixel, sync and blanking pipeline is unchanged. This change
does not synchronize separately programmed GDC fields into an atomic software
transaction; it makes each sampled set of fields cross the clock boundary
coherently. CPU register access is unchanged.

`pc98-video-settings.sdc` bounds only the held payload paths to 20 ns. Capture
is at least two complete 75 MHz video periods after launch (26.66 ns), leaving
6.66 ns of settling margin. Only the first request/acknowledgment synchronizer
inputs and the four local reset synchronizer CLRN pins have false paths.
All later stages and CRTC consumers retain normal timing checks. Register and
pin collection guards reject a missing or incomplete transfer in Quartus.
The logical map is 121 bits. `GRAPHSCR98` declares but does not consume its
ten-bit `LINENUM1` input, so synthesis removes bits 95..104 in both banks.
The guard requires every one of the other 111 bits individually, allowing
register replication without masking a missing field. No live field is
exempted from timing.

The regression checks coherent sequence patterns, hot writes, reset, stable
outputs between video edges, and final delivery within one microsecond. A
20 ns transport-delay variant passes CPU rates 20/40/50/60/90/100 MHz at three
phases each. Late payload, early capture and live source bypass negative
controls fail. The separate top-level mapping test compares 10,122 vectors
across all 19 fields, including one-hot bits, and rejects swapped graphics
and text pitch. These tests do not establish full-core operation at those
clock rates. Full-core fitting and hardware game validation remain pending.

The MiSTer wrapper also uses this transfer with WIDTH=2 for the scaler's
low-latency and filter-mode bits. It samples the original host framebuffer/
filter selection in `clk_sys`, then supplies `ascal.mode[3:2]` from the input
video clock (`clk_ihdmi`, 75 MHz in this core). Mode bits 4 and 1..0 remain
zero. Host configuration gains the same bounded latency; image dimensions,
pixel data and selected filtering are unchanged. A separate, root-instance
constraint bounds those two held payload bits, the two control synchronizers
and the four reset-release CLRN pins. It does not relax other scaler paths.

The transfer regression now runs the two-bit and 121-bit instances together
and compares their matching bits on every video edge, including delayed data
and reset. The existing integer-scaling and actual wrapper viewport tests
also pass. The default HDL Docker image now includes Python for the top-level
mapping check. Physical timing and hardware validation of the scaler-mode
instance are pending.

## SDRAM display-page selection

The CPU-written display-page bit formerly fed the SDRAM row-address mux
directly. PaletteTransfer60 reports -0.114 ns on that path. The separate
`display_page_address` entity now synchronizes this single bit with two
100 MHz memory-clock registers and a local reset-release chain. Its second
stage selects the original front/back page constants. Pixel addresses retain
the existing held graphics request protocol, and no SDRAM transaction cycle
is added. Page changes gain synchronization latency; this is not a frame-boundary
page-flip mechanism.

Only the CPU bit to the first stage and the reset synchronizer's two CLRN
pins are excepted. The second stage, row mux and all memory consumers remain
normally timed. The real SDRAMC/GRAPHSCR integration regression switches pages
while CPU traffic competes with 640 graphics bursts. It checks page selection
at the physical SDRAM pins and the page/word/plane identity of all 2560 returned
words, accounting for both MEMADR and PMEMADR registers. All 36 CPU-rate/phase
combinations pass at 20/40/50/60/90/100 MHz and six pixel phases, with the existing
20 ns address/data delay tests. Reset selects the front page even if the CPU
input starts high. Late-data and live-page-bypass negative controls fail.
These tests do not establish full-core operation at 90/100 MHz. Physical timing
and hardware tests of this new page synchronizer are pending.
