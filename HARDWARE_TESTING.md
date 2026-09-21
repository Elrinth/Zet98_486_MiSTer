# Hardware testing

Test device: SuperStation One with SuperDock and 128 MB SDRAM. The initial
test system uses ConsoleMode's MiSTer executable (ConsoleMode 1.1.4.2).
The TV is connected by HDMI through a switch box. Console Mode output with HDR
was initially stable, later also glitched, and recovered after the user powered
the equipment fully off and on. Keep the recovered display as the control
during core video debugging. The inspected profiles use `direct_video=0`, `video_mode=0`
and `vsync_adjust=0`; the main profile has `hdr=1`.
No credentials, machine BIOS, game images or private screenshots belong in Git.

## Isolated baseline

Use a separate `games/Zet98_Test/` folder and `config/Zet98_Test.CFG`.
An MGL launcher with `<setname>Zet98_Test</setname>` makes MiSTer use this
folder and configuration without replacing the normal Zet98 installation.
For example, using the repository's unmodified upstream 2022 RBF:

```xml
<mistergamedescription>
  <rbf>_Computer/_Zet98_Test/Zet98_Upstream2022</rbf>
  <setname>Zet98_Test</setname>
  <file delay="2" type="s" index="0" path="rusty-system.d88" />
  <file delay="2" type="s" index="1" path="rusty-opening.d88" />
  <reset delay="3" hold="1" />
</mistergamedescription>
```

Supply `boot.rom` in that game folder. Use copies of the disks, since the core
can write to mounted images. The existing 2021 RBF and normal `games/Zet98/`
files remain intact. MGL syntax and folder behavior were checked against
MiSTer Main's MGL parser and `user_io` implementation.

Rusty's system disk displays an MS-DOS 3.30D banner and a Japanese warning
when the GDC graphics clock is configured as 5 MHz. It requests **2.5 MHz**
and a restart (DIP SW2-8 off). In this core's OSD, select `DIP2-8 GDC clock:
2.5MHz`; the corresponding MiSTer status bit is 22. This graphics-controller
setting is separate from the CPU clock being upgraded.

## Observations, 2026-09-21

- The user-supplied development ROM reaches MS-DOS with Rusty's system disk.
  User photos establish this; initial remote captures did not establish boot.
- After setting GDC to 2.5 MHz, the user heard Rusty's startup audio. The game
  requested System Disk plus Opening Disk; the test launcher was corrected
  to mount that pair. This establishes loader progress, not full gameplay.
- The displayed text intermittently shifts/overlaps, and a photograph shows
  a mostly white frame. Cause is not yet established. These observations
  precede deployment of the ao486 test RBF.
- The original 2021 core initially produced a black remote screenshot.
  Subsequent MGL tests produced no screenshot file; the documented scaler
  header at physical address `0x20000000` read as all `FF` on the 2022
  reference test. Remote screenshot failure must not be interpreted as a
  black physical display.
- The installed downloader-generated ROM and the known-working development
  ROM both have the expected 550,912-byte length, repeated final 32 KiB BIOS
  bank, and 128 KiB zero padding. Their BIOS/font contents differ. Layout
  checks do not establish compatibility of the downloader ROM.

Local ROM fingerprints, for reproducing this comparison without distributing
the files:

- Known-working development ROM SHA-256:
  `647b5fa95a1a55096728829b74d4729e45adfd49d8e3a86aabf486a042f21db7`
- Existing installed ROM SHA-256:
  `4ba8a89bca02acd634a1df424dce28f16556e3632259e2e8c8769252b9533c8b`

## First ao486 build

Local snapshot: `build/quartus-20260920-235936-1cbf34/source`.
Quartus Lite 17.0 completed compilation in 25m16s. The build driver correctly
rejected the result because timing checks failed; see the README for resource
and timing figures. The RBF SHA-256 is
`7dab7fcba85690878b104bef9cf2888329ee7e9b348dcd4b697e8351cf7b1e3c`.

The test image was uploaded under the separate name
`_Computer/_Zet98_Test/Zet98_486_20260921_test.rbf`; its device checksum matched.
SSH confirmed the running image and mounted System/Opening disk files.
The user then supplied photos of DOS sound-driver initialization and the
C-Lab logo, and confirmed the logo on screen. This is the first ao486 hardware
boot milestone. Severe horizontal corruption and white frames persisted.
The loader subsequently showed a file-not-found prompt asking for System and
Opening disks despite both files being open in MiSTer; that remains unresolved.

### Power-cycle recovery

The user subsequently reported that corruption persisted after returning to
Console Mode. Fully powering the equipment off and on restored the display.
This demonstrates recovery without deploying a new RBF, but does not identify
which device retained the bad state or which operation triggered it. Previous
warm-load comparisons alone cannot establish a PC-98 rendering defect.
Read-only SSH inspection after this report confirmed a fresh system uptime,
Console Mode running, no mounted test disks, and the preserved GDC 2.5 MHz
configuration. The unchanged upstream 2022 reference was then reloaded with
the same ROM and System/Opening disks, confirmed open through SSH. A screenshot
file could be saved again, but contains only black pixels; this remains
insufficient evidence about the TV picture. The user then confirmed stable
positioning, with a readable file-not-found prompt. The startup sound was heard,
but the logo interval appeared white, so graphics correctness is unresolved.

First retest the already-deployed PC-98 images against the recovered control.
Record whether corruption begins when entering PC-98 and whether it persists
after returning to Console Mode. Do not attribute the recovery to source
changes that have not been loaded.

### Optional video diagnostic

The prepared diagnostic build uses Zet to isolate video changes. It includes a
registered video-output stage, a cheaper text scanline calculation, and OSD
`Video test: Color bars` (status bit 3). The pattern bypasses PC-98 text,
graphics and SDRAM fetches, but uses the same video PLL, scaler and HDMI path.
It runs without waiting for the PC-98 BIOS. Full-screen scaling is also present
in that source. Hardware results are pending; deployment was held after the
power-cycle recovery so the existing images can be compared first.
The first video-test snapshot is `build/quartus-20260921-004058-4b8287/source`.
Compilation finished with 20,358 / 41,910 ALMs (49%), 380 / 553 RAM blocks,
and 61 / 112 DSP blocks. Timing failed: 11 negative-slack checks, worst
`-25.828 ns`. The detailed report's worst path crosses from the Zet CPU to
SDRAM write data; CPU-register setup paths alone pass with `8.148 ns` slack.
This RBF has not been deployed and is not a verified release.

### DOS disk probe

`tests/hardware/disk_probe.asm` is an 8086-compatible DOS shell diagnostic.
Assemble it with NASM `-f bin`, then use `scripts/d88_file.py` to replace
`BOOT.COM` in a **new copy** of the supplied system D88. The replacement must
fit the old file length. The tool preserves the FAT, directory entry, sector
metadata and all unrelated payloads, and refuses to overwrite an output file.
No supplied disk or BIOS is distributed with this program.

The first probe ran on the unchanged 2022 reference with System on FDD0 and
Opening on FDD1. The user supplied a clear, stable photograph showing:

- Default DOS drive A; `A:\SYS_DISK` opens and reads `0D 0A 1A`.
- `A:\OP_DISK` and `A:\MGXLOAD.BIN` return DOS error `0002` (file not found),
  expected for the System disk.
- All three corresponding paths on B return `0003` (path not found).
- The probe reports completing its log write, but the retrieved D88 contains
  no log file. Host-image write persistence is not established.

Version 2 adds the BIOS drive mask at `0000:055C`, DOS drive count, and a B:
free-space query. A trial launcher mounted Opening first, waited eight seconds,
mounted System, then waited another eight seconds before reset. The user
reported a black screen and constant beep rather than diagnostic output.
The test was immediately stopped by returning to Console Mode. This trial
changed both the probe and mount order, so it does not isolate which caused
the failure. Use the earlier System-first order for subsequent probe comparisons.

### Startup speaker mute

The user requested quiet startup while retaining later PC-speaker sound.
`Startup mute: 10s / Off` now defaults to ten seconds after core start/reset.
Only the beeper input to the audio mixer is gated; FM/PSG paths and PIT operation
are unchanged. The timer continues while bypassed and saturates after expiry,
so later menu changes do not restart it. Simulation passed exact duration,
automatic restoration, reset, bypass, and saturation checks.
Quartus Analysis & Elaboration also passed for the ao486 source snapshot
`build/quartus-20260921-011511-1dccf1/source` (0 errors). The feature is now in
the DiskFix test RBF described below. Audible hardware confirmation is pending.

### Per-drive HPS acknowledgement fix

Source inspection found that `hps_io` returns four acknowledgement bits, but
the wrapper connected them to a scalar wire. Only slot 0 reached the disk
engine; slots 1–3 could never complete their host transfers. The disk engine
serializes image operations, so a stalled Opening-disk load can also prevent
later System-disk writes. This can prevent Opening-disk loading and is
consistent with the mount-order stall. The hardware retests below confirm
writeback and, after allowing image-loading time, DOS access to both drives.

The wrapper now retains all four bits and ORs them for the serialized legacy
engine. All slots explicitly request one 512-byte block. Mount read-only
metadata is also passed at its actual scalar width and replicated for the
legacy input; this does not add enforcement of host read-only state in the
disk engine.

The real wrapper/HPS regression passes reads and writes on all four slots
(4,096 bytes total), ACK lifetime, LBA, block count, and mount metadata. A
negative control restoring only the scalar ACK fails at slot 1, as expected.
The existing adapter, peripheral, video and startup-mute tests also pass.
The next ao486 build snapshot is `build/quartus-20260921-013307-8d60fc/source`.
Compilation completed in 24m48s with 32,146 / 41,910 ALMs (77%), 395 / 553
RAM blocks, and 63 / 112 DSP blocks. Timing still fails: 11 negative-slack
checks, worst `-22.883 ns`; CPU-register paths alone pass with `19.854 ns`
slack. This is an experimental diagnostic build, not a verified release.

RBF SHA-256: `eab37f279929baef8181551c767ad5bbfaf7b690295cd73eea878ae81e548721`.
The device checksum matched after upload as
`_Computer/_Zet98_Test/Zet98_486_DiskFix_20260921.rbf`. It includes startup
mute and the video-output/text-row changes, but not the later DMA bus rewrite.

A fresh v1 probe image was launched with System first, Opening second and a
three-second reset delay. Both host images were open. After boot/writeback,
the retrieved System image contains `Z98DIAG.TXT`: A:\SYS_DISK reads correctly,
but all B: paths still report `0003`. This proves actual DOS log persistence
to the host D88; it does not prove second-drive access. A follow-up using the
same program/core with a fresh System image and a 60-second reset delay
succeeded. The retrieved log shows `B:\OP_DISK OK read=0000` and
`B:\MGXLOAD.BIN OK read=0010`; the sixteen bytes read match the original
Opening image exactly. `B:\SYS_DISK` now returns `0002` (missing file), as
expected on a valid B drive containing the Opening disk. This isolates the
reset delay as the remaining cause in this probe comparison. Keep a 60-second
delay for now; the minimum safe delay and faster image loading remain unmeasured.

Rusty was subsequently launched on the same DiskFix RBF with System/Opening
images and that 60-second reset delay. It resets once after the initial wait.
The user confirms a correctly displayed C-Lab logo and opening cutscenes, but
reports extremely poor performance. This proves further game loading and
visible intro graphics, not satisfactory gameplay speed. Startup-speaker
confirmation and a repeatable gameplay measurement remain pending.

### DMA byte-lane feedback removal

The detailed baseline timing report explicitly includes a combinational loop
through `dbus`: the high-byte fallback reads the final low byte, and vice versa.
In the 20 MHz Zet video-test fit this contributes 22.254 ns of a 34.838 ns
data path, against a 10 ns system-to-SDRAM clock relationship. The first ao486
fit also reports the bus loop on its failing CPU-to-SDRAM paths.

The revised source resolves each lane's normal device priority into a data byte
and a driven flag. DMA then copies the selected source byte only when the
destination lane has no primary driver. There is no cross-coupling of final
outputs. The actual top-level expressions match the historical bus in 57,748
simulation cases, including device-enable pairs, lane masks, CPU/DMA ownership,
and FDC bytes sent to/read from even and odd memory addresses. A deliberate
routing-error control fails the test. This is mux equivalence, not a full DMA
controller simulation or hardware result.

The separate timing-comparison snapshot is
`build/quartus-20260921-014115-47680a/source` (ao486, 20 MHz). Compilation
completed in 25m32s with 32,458 ALMs (77%), 395 RAM blocks and 63 DSP blocks.
Worst reported slack improves from -22.883 ns to -5.493 ns, with nine negative
checks remaining. CPU-register setup alone passes at +20.828 ns. Both snapshots
report 27,077 registers before fitting. No combinational-loop warning appears
in the new build. Remaining critical paths include video counters feeding
system-clock peripheral write inputs through the shared data bus.

RBF SHA-256: `0889dc674ab81d1ce76e0fc28f918ba1113a581e8db0f3b5135a0f75bc18fc53`.
It includes the disk ACK fix and startup mute, but is not deployed; Rusty's
confirmed intro is on the earlier DiskFix snapshot without this bus change.

### Pixel-clock constraint audit

The inherited SDC does not constrain the `VTIMING.clk3sft[2]` clock, which
drives text/graphics logic and SDRAM video requests. It rotates `001` at
75 MHz, producing a 25 MHz clock with one-third duty cycle. Its reset permits
three phases relative to the other PLL clocks.

`scripts/report-pixel-timing.tcl` adds all three possible generated-clock phases
to a completed timing netlist for investigation. It does not change the saved
project constraints or RBF. Running this audit on the completed Zet video-test
fit exposed setup failures from text addressing into the font RAM clocked at
75 MHz (`-5.082 ns`) and from the system-clock text GDC into pixel logic
(`-4.291 ns`). These paths were previously unconstrained. The audit adds no
data-path exceptions; inherited constraints remain in force. The three mutually
exclusive phases are excluded only from timing against each other.
The saved audit script reproduces these setup results and also reports hold
failures from/to the pixel clock (`-0.277 ns` / `-2.621 ns`).

These are additional outstanding timing issues, not evidence that the bus fix
failed or that the user's display symptoms have one established cause. The
audit on the new ao486 bus-rewrite fit reports setup from/to the pixel clock
of -7.136 / -5.520 ns and hold of -0.175 / -2.384 ns. These are additional
checks beyond its ordinary nine negative checks. Full production constraint
coverage remains unfinished.

### Instruction-cache performance work

The DiskFix RBF that shows Rusty's intro still disables the instruction cache.
The new source enables caching only below physical address 80000h. Upper and
banked windows remain uncached. CPU writes use the existing instruction snoop;
external DMA ownership and bank-window writes aliasing fixed RAM invalidate
prefetch and all cache tags. An outstanding fill drains before tag clearing.
This is an instruction-cache change, not the upstream platform's L2/data cache.

The DMA arbiter previously required a falling CPU-strobe edge before granting
ownership. Cached execution or HLT can leave the bus idle indefinitely, so DMA
now acquires an already idle bus while still waiting for an active CPU transfer.
The cache/map/DMA regressions and the full CPU smoke test pass. The latter needs
590 legacy transfers versus the original uncached run's 1,822; this is a test
program, not a Rusty performance measurement.

The full CPU benchmark with eight simulated memory wait cycles reports an ALU
loop of 434,005 cycles / 32,833 transfers with cache disabled and 6,361 / 17
with cache enabled. A VRAM-write loop changes from 114,260 / 8,641 to
6,463 / 417. Both verify output checksums. These deliberately small hot loops
expose repeated code-fetch costs; their ratios must not be advertised as Rusty
speedup. The memory model does not include the complete SDRAM/video arbitration.
The negative control with external invalidation disconnected fails on stale
code, confirming that the coherence test actually exercises cached instructions.

Quartus Analysis & Elaboration passed before the small DMA idle-grant change.
The complete build including it is in
`build/quartus-20260921-022919-fb952a/source`; compilation/timing and hardware
results are pending. An earlier cache build was deliberately stopped to include
the DMA grant fix. No 66/100 MHz performance claim is established.

`tests/hardware/cpu_bench.asm` is an 8086-compatible DOS benchmark for an isolated
System disk. It uses the DOS clock, checks results and saves `Z98PERF.TXT`.
Version 1 completed on DiskFix with 131,072 iterations in 200 hundredths for
ALU and 500 hundredths for RAM copy. Both checksums passed. The reported clock
appears to have whole-second resolution, so the revised v2 synchronizes to a
clock transition and repeats 131,072-iteration blocks for at least ten reported
seconds. Each kernel must still take less than one hour. This measures neither
Rusty frame rate nor original 486 equivalence.

The uncached v2 baseline was launched at 02:38:43 local time with a single
disposable disk and a 60-second reset delay. The retrieved host D88 contains:
ALU **4 blocks / 1100 hundredths**, RAM copy **2 blocks / 1100 hundredths**,
and passing checksums. Each block contains 131,072 iterations. Baseline and
future cache-test disks start byte-identical; only BOOT.COM's allocation differs
from the supplied System image. The cache build has not yet been deployed.

An independent CPU/adapter 66 MHz feasibility fit is also running under
`build/cpu-probe-66-20260921`. `scripts/probe-cpu.tcl` uses virtual pins and
one-nanosecond input/output delays; it is not a board design or a deployable RBF.
Its register timing and unconstrained-path reports distinguish CPU headroom
from the still-unresolved platform clock crossings. Results are pending.

Keep BIOS, disks and settings identical when comparing Zet and ao486.
Still required: reliable complete floppy/game loading, Rusty gameplay,
repeatable scene timing, sound pitch/tempo, and video stability. Neither the
initial logo nor successful FPGA fitting measures Rusty speed.
