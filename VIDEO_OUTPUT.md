# PC-98 display options

The core exposes the actual 640x400 picture to MiSTer's HDMI scaler. The
previous 640x480 capture included 80 permanently black lines above it.
Changing capture DE does not change native RGB, pixel frequency or sync.
Color bars retain their separate 640x480 diagnostic raster.

`HDMI scaling` has three choices. The new default, **V-Integer**, preserves
the selected aspect ratio and scales vertically by a whole number.
**HV-Integer** also chooses a whole horizontal multiplier nearest the desired
aspect ratio. **Aspect** uses the ordinary MiSTer aspect fit.

At 1920x1080, a 640x400 picture with 4:3 selected occupies 1066x800 pixels in
V-Integer mode, or 1280x800 in HV-Integer mode. The latter has uniformly
replicated pixels but is wider than 4:3. Borders are intentional. Use a
sharp/nearest-neighbor MiSTer video preset if softened pixels are unwanted.
Output resolution remains a MiSTer setting; `video_mode=8` selects 1080p60.
No global HDMI/HDR or television configuration is changed by the core.

The MiSTer scaler interface uses 13-bit aspect outputs; bit 12 marks explicit
viewport dimensions. The old 8-bit interface could not carry these sizes.
The standard helper's narrow-image comparison is fixed to avoid unsigned
underflow when the desired aspect width is below one native source width.
Tests check 720p, 1080p, 1440p and both 400/480-line inputs.

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
and clock enable have the same two-clock pipeline latency.
