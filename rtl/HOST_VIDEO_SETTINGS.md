# Host settings across video clocks

The FullFont60 fit at 4790ba7 failed timing on slow host-setting paths into
75 MHz video: scaler mode, VGA OSD coordinates and the framebuffer enable.
Its two-register multibit pipelines did not provide a held-data protocol.
They could not safely be declared asynchronous merely to remove a violation.

`video_config_snapshot.sv` now holds an entire source-clock snapshot, toggles
a request, and leaves that snapshot unchanged until a returned acknowledgement
has crossed two source-clock registers. Two destination registers precede
the enabled payload capture; acknowledgement changes at that capture.
Changes while busy coalesce to the latest source value. This is appropriate
for settings, not FIFO data or events that must all be delivered.

The snapshot serves both OSD instances, the framework viewport (including
dimensions, free scaling and custom aspects), and PC-98 scaling mode/custom
aspect. HDMI width/height already originate in the video domain and retain
their local pipeline. The OSD/framebuffer command interfaces, pixel datapaths,
scaling arithmetic and crop-at-VS behavior remain unchanged. A snapshot is
coherent at one source edge; a sequence of separate HPS writes is not turned
into a single atomic command transaction.

Both handshake domains initialize at FPGA configuration. Neither handshake
side is independently reset by a guest CPU reset. Stopping either clock
preserves pending data and resumes the same transaction when it restarts.

`pc98-host-video-settings.sdc` constrains every realized held-to-captured
payload bit to 5 ns. The tested target clocks are 75 MHz input video and
148.5 MHz HDMI; capture follows at least two destination periods. A delayed
first synchronizer sample increases settling time. Only the first request/
acknowledgement synchronizer stages have asynchronous control exceptions.
Payload hold uses the acknowledgement contract instead of the unrelated
nominal clock-edge relationship. Payload setup and downstream consumers are
still checked. Missing named instances or control endpoints stop timing
analysis; optimized constant/unused payload bits need not remain as flops.

The separate one-bit test-pattern and HDMI-tune enables already use two-stage
synchronizers. Their first-stage exceptions do not relax the next stage,
pixel consumers, or the measurement clocks. An FPGA fit and inspection of
the actual surviving endpoints are still required; RTL simulation does not
prove analogue metastability resolution or physical routing delays.

Validation:

- 144 snapshot cases: 20/40/50/60/90/100 MHz source clocks; 75/148.5/200 MHz
  video clocks; four relative phases; 0/5 ns skew on half the payload.
  Rapid updates, stopped clocks, acknowledgement stability and delivery of
  the final value pass. Overwriting busy data, bypassing held data, capturing
  a request too early, and 100 ns late payloads are all rejected.
- The actual framework viewport passes 73 rectangles at each of 50/60/90 MHz
  source clocks, including live framebuffer coordinates and normal/native/
  integer/custom/free-scale modes. A raw-input bypass is rejected.
- Both OSD clock-ratio cases match the legacy OSD over 3,411,200 pixel/sync
  comparisons, with all four rotations, info/menu/disabled modes and
  640x400/320x200 inputs. A raw-settings bypass is rejected.
- Existing native scaling/crop, HDMI tune-gating, diagnostic raster and
  disk/IDE/MIDI wrapper regressions pass. The native analogue pixel path is
  not cropped by these changes.

Logs are local build artifacts: `build/video-config-regression.log` and
`build/ascal-address-prepare-final.log`. Hardware remains on the previously
verified FullFont50 build until a new fit passes its timing checks.

The b700d62 HostSettings60 fit contains all four snapshots (132/132 OSD
bits for each OSD, 150 viewport bits and 27 scaling bits). Their payload
setup bounds pass. Its remaining 75 MHz failure is instead floppy activity
feeding the overlay's existing two-stage synchronizers. Both independent
activity bits and the enable now have first-stage-only exceptions, with
preserved synchronizer stages; pixel/animation logic remains timed.

Reanalysis of that unchanged fitted database accepts the three named
endpoints and reports +1.778 ns as the worst slow/hot incoming-video path.
All 59 floppy animation frames, captions and 56,576 streamed pixel/sync
comparisons still pass. The independent cold HDMI limit is a palette-RAM
output through luminance arithmetic (-0.002 ns), not the earlier line-address
subtraction. The database still has CPU/memory failures and is not deployed.
See `build/host-settings60-domain-audit`; this constraint audit includes
neither the newer decoder arithmetic nor SDRAM handshake RTL.

The cdf93b9 MaskGrcg60 fit exposes a separate measurement path in `video_calc`:
direct sampling of the width/height registers from 75 MHz video into the
60 MHz system clock misses timing by 0.088 ns. Direct sampling also has no
protocol to ensure that changing multibit measurements remain coherent.

`video_calc` now uses two instances of the same snapshot module. One carries
the 74-bit resolution/interlace/change-count tuple from video; the other
carries four 32-bit timing measurements from the 100 MHz measurement clock.
Both deliver to `clk_sys`, before the existing parameter mux. The mux's
parameter numbers and response cycle are unchanged. Measurements can arrive
a few handshake cycles later, and intermediate updates can coalesce; this
interface reports the latest measurements rather than every scanline event.
Separate source-clock snapshots do not imply that a whole sequence of HPS
parameter reads is atomic.

The same 5 ns held-payload bound and first-stage-only control exceptions cover
these two named instances. Missing endpoints still fail the constraint guard.
The generic handshake's stopped-clock and skew tests apply; the actual
`video_calc` measurements and disk-interface compilation also need regression
checks before fitting. Physical timing and hardware output remain unverified
for this change.

The new measurement connections passed the actual `video_calc` test at
20/50/60/90 MHz system clocks, including both tested widths, height, line/
frame/pixel times, HDMI frame time and the mode-change counter. All 144
generic snapshot skew/phase/stopped-clock cases and their negative controls
passed again, as did the disk/IDE/MIDI wrapper regression. The constraint
guard tests pass with six snapshot instances and still reject missing or
ambiguous handshake endpoints. This is functional/constraint-scope evidence;
the new routed design must still satisfy the physical payload bounds.
