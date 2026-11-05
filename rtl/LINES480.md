# 640x480 (PC-9821 31 kHz 480-line) display

The raster stays 800x525 at a 25 MHz pixel clock (~31.5 kHz, 59.5 Hz). In
480-line mode the first visible line moves from 125 to 45, so all 480 lines of
a VGA-like frame are shown; otherwise the 400-line window is unchanged.

**Selection:** the text GDC latches its SYNC active-lines parameter (P7/P8,
AL). AL above 400 sets `LINES480` (`Zet98/GDC/txtgdc.vhd`). This is what the
PC-9821 BIOS (INT 18h AH=30h, BH bits 5-4 = 11b) and software that programs
the GDC directly send: AL = 480 (or 475 for 25 rows). Power-on and 400-line
SYNC tables keep the 640x400 window.

**Path:** `r_LINES480` (CPU clock) -> `video_lines480_sync` (two video-clock
stages, `Zet98/v17/pc98-lines480.sdc`) -> CRTC98 parent-clock staging -> a
pixel-clock latch at frame start (VCOMP), so no frame mixes heights. The
resulting first visible line (`FIRSTV`) drives synccont2 (DE/VISIBLE and VRTC),
the text layer (knjscr, text_row_counter), GRAPHSCR98 and pegc_raster.

**What shows 480 lines:** text (e.g. 30 rows of 16 lines) and PEGC 256-colour
packed graphics (use single-page mode, 6Ah = 69h, since 640x480 bytes exceed
one 256 KB page). The 4-plane 16-colour VRAM is 32 KB per plane and wraps at
line 409, as on PC-9821 hardware, where 480-line graphics are 256-colour only.

**Port 09A8h:** a readable latch (bit 0, 31 kHz select). The core always scans
at 31 kHz; BIOSes use the decoded port (reads 00h/01h instead of FFh) to detect
this support.

**VRTC** is high for the 45 lines before the first visible one (1.44 ms), the
IRQ2 edge stays at the end of the visible area. The HDMI scaler measures DE,
so fit/integer scaling adapt automatically (1440x1080 fit, 1280x960 2x).

Tests: `tests/run-crtc-lines480.sh` (visible lines, text on every row, VRTC
width, switching only at frame boundaries) and `tests/run-txtgdc-lines480.sh`
(SYNC AL decode). Existing CRTC, graphics-address, PEGC, text and timing
benches pass unchanged.
