# CPU and peripheral simulation

The I/O adapter targets the native byte-address/length interface of MiSTer
ao486 commit `9d888c485bcf2e781824b303588668529a02015e`. The adapters are connected
to the optional ao486 build; simulation does not establish faster game performance.

It retains PC-98's low/even and high/odd byte lanes, preserves aligned 16-bit
register accesses, and splits unaligned and 32-bit transfers. The peripheral
fabric now decodes both selected lanes independently in the Zet98 top level.
CPU and peripheral clocks are the same in this unit test; a clock-domain
bridge is still required for independent CPU and peripheral rates.

The memory adapter converts DWORD-addressed reads of up to eight beats and
single writes into acknowledged 16-bit transfers. It preserves all 32 physical
address bits; BIOS aliases and PC-98 memory mapping are deliberately left to
the system integration. Multi-beat reads return full DWORDs because ao486
instruction fetches can carry byte enables left over from unrelated data reads.
Single-beat byte/word reads omit an unused halfword, returning FFFF there. The
real upstream-master integration checks that these reads use one transfer and
that instruction fetches still use sixteen transfers per eight-DWORD burst. Write
burst counts can likewise reflect a pending read; each write is still a single
DWORD command, split according to its actual byte enables.

The memory bridge also skips the state-machine steps for empty halfwords.
It still waits for ACK to fall after each real transfer and drains writes
before granting I/O. `tests/run-memory-bridge.sh` compares the same 603-command
workload with this optimization enabled and disabled, checking all data and
side effects in both runs. With narrow reads it reduces 17,496 clocks to
17,076 (420 fewer); without narrow reads it saves 210 clocks on writes.
The full ao486 CPU and cache tests also pass, including DMA changes,
self-modifying code, upper-memory bypass and interrupt/IRET. This is simulation
evidence; the change has not yet been benchmarked in hardware or Rusty.

`ao486_bus_bridge` arbitrates the two adapters onto one memory/I/O bus. It drains
pending memory commands before granting I/O, including the second command of
an unaligned ao486 write. A granted I/O transaction retains ownership through
every halfword and the final acknowledgement release.

From the repository root in PowerShell 7, `./scripts/test.ps1` runs the
adapter/peripheral suite, followed by real CPU, cached REP, extended-memory,
cache-coherence and upper-RAM instruction-cache regressions. It uses the
installed `zet98-mixed-sim:latest` image (GHDL 4, Icarus, NASM and Python).
Install that toolchain once when setting up a new machine:

```powershell
docker --context desktop-linux build -t zet98-mixed-sim:latest -f tests/Dockerfile.mixed tests
```

Test runs copy a source snapshot into Linux container storage and default to
one CPU, 2 GiB RAM, no extra swap and no network. They save the image ID,
commands, source snapshot, logs and result under `build/simulation-*` and
remove the container after collecting its logs. Docker commands have finite
deadlines. An existing FPGA, simulation or timing job prevents another from
starting; an observation timeout never triggers an automatic replacement.

CPU tests obtain Intel models from the selected installed Quartus image using
a never-started container; per-run model copies/hashes remain in ignored build
output. BIOS/game files are not included. `-AdaptersOnly` skips the CPU stages
and Intel-model dependency. To run focused adapter tests:

```powershell
./scripts/test.ps1 -AdaptersOnly -TestScript tests/run-video-config-snapshot.sh,tests/run-framebuffer-viewport.sh
```

`-PrepareOnly` creates the source snapshot without Docker. `-StartOnly` starts
a detached job and records its container name/ID; inspect that same container,
save its logs/results and remove it when finished. It must not be treated as
a successful test until its final exit status and test log are checked.
See [resource controls](../scripts/DOCKER_RESOURCE_LIMITS.md).

`tests/run-video-counters.sh` checks the values sampled by pixel-clocked
consumers over complete frames at six reset phases. It checks every raster
coordinate and line/frame pulse before delta-cycle updates, preserving the
sampling behavior while removing VTIMING's 75 MHz output staging. The
text-memory, text-row, reset and retrace tests cover its downstream users.
The floppy-overlay test also checks that a changed crop does not move the
indicator until vertical blank, while retaining all 59 frames and captions.

The bench checks byte, word and dword transfers at even/odd addresses,
16-bit port-address wrapping, correct peripheral byte-lane side effects,
wait-state stability, acknowledgement release and reset during a request.
The memory bench checks all 16 write masks, bursts of one through eight DWORDs,
addresses above 1 MB and at the 32-bit wrap boundary, queued requests, stalled
transfers, acknowledgement release and reset during a burst.
An additional integration bench uses the unmodified upstream `avalon_mem`
request generator. It verifies unaligned data reads/writes, complete eight-beat
instruction fetches with unrelated byte enables, byte/word DMA transfers through
the ao486 DMA input, and concurrent I/O with pending memory traffic. This does
not yet connect Zet98's existing external DMA controller or the full ao486 CPU.
The combined adapter also passed standalone Quartus 17 Analysis & Synthesis
for `5CSEBA6U23I7` on 2026-09-20 (347 logic cells before fitting). This is a
synthesis compatibility check, not timing closure or a complete core build.
The VHDL bench also compares OPNA/PIT enable rates and the VFO interrupt pulse
width at 20 and 40 MHz. These tests do not verify complete machine integration, BIOS boot,
complete peripheral timing, or Rusty performance.

Video regressions check the replacement text row counter against the original
absolute-line modulo formula over 33,600 scanlines (all 32 character heights,
two full frames each). The registered video-output test checks native RGB/sync
alignment and hold behavior, plus the diagnostic raster's 800x525 total size,
640x480 active area, sync pulse widths, blanking and divide-by-three pixel
enable. These are logic tests; they do not establish hardware video stability.
An integration test with the original `VTIMING` generator also checks row
alignment for 1,247,400 pixels across 16-, 20- and 32-scanline text modes,
after its initial partial scanline on reset.
The retrace-domain test drives the original raster and checks horizontal and
vertical status at both 20 and 40 MHz: edges arrive within 100 ns, change only
on destination clock edges, and clear on reset across more than two frames.
It verifies logical synchronization, not physical metastability or timing.

The floppy-overlay test verifies rotation, the lower-right position at two
raster sizes, idle/disabled passthrough, activity hold/expiry and unchanged
sync/blanking/pixel-enable timing across eleven frames.

The startup-speaker mute test verifies minimum expiry, deferred restoration
until a long boot beep ends, later software tones, timer saturation, reset
rearming and the menu bypass. Changing the bypass
after the startup interval must not mute later speaker audio. Clock and duration
generics are reduced for simulation; the core uses its system clock frequency
and a 10,000 ms interval.

`run-audio-decimator.sh` drives `rtl/audio_decimator.sv` with a 10 kHz tone at the
OPNA rate and 13 kHz at 44.1 kHz on a 24.576 MHz clock, samples the output at
48 kHz like the framework and checks the spectrum: tone level within 0.5 dB and
every alias at least 65 dB down, while the bypass instance must show the aliases
and a boxcar-only filter must fail.

`run-pcm86.sh` verifies the experimental PCM86 playback module: signed samples
in all six audible 8/16-bit mono/stereo formats, a complete 32 KB FIFO with
wrap and concurrent refill, held I/O writes, full/empty/reset, volume/mute,
and interrupt threshold/acknowledge/masking. The rate test checks all eight
fractional sample rates at 20/40/50 MHz. The PIC regression independently checks
shared FM/PCM IRQ12 levels. `hardware/pcm86_probe.asm` checks the board ID,
32 KB full/empty/reset status and two real PCM interrupt deliveries, then saves
`Z98PCM.TXT` on a disposable DOS disk. It keeps PCM muted and does not validate
the audible output or game compatibility.

`run-disk-interface.sh` drives real HPS commands through the core's actual
SystemVerilog wrapper and `hps_io`. It transfers 512-byte reads and writes on
each of four image slots and checks per-slot/shared ACK lifetime, LBA, the
single-block request size, buffer payload/address and mount metadata. The
machine and Intel clock primitives are stubs; the bench does not exercise the
VHDL floppy controller or real disks. Unrelated PS/2 and configuration-ROM
logic is disabled in the bench. A temporary `hps_io` copy supplies parameter
defaults required by Icarus; both values are overridden by the actual instances.
This catches the previous scalar ACK connection, which discarded slots 1ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ3.

`run-data-bus.sh` compiles the marked data-bus expressions directly from the
machine top level. Its reference is the historical mux before DMA feedback
removal, preserved under `reference/`. It compares 77,748 cases: every pair
of device enables, all byte-lane masks, CPU/DMA ownership, interrupt-acknowledge
gating, sparse random selections, and both DMA byte-routing directions.
Directed FDC-to-memory and memory-to-FDC cases check even/odd byte placement.
It also compares each selected CPU I/O write byte (including loader precedence)
against the historical shared bus. This verifies the direct write path while
unrelated peripheral read enables and DMA ownership vary. An additional 20,000
DMA memory-to-FDC and FDC-to-memory comparisons cover both byte addresses and
memory-device priority. The actual GRCG is also instantiated: 4,096 plane
results check CPU/DMA write masks against delayed memory read data, and tile
comparison checks distinguish matches in the high and low bytes on every plane.
This verifies mux behavior; it does not simulate the complete DMA controller.

`hardware/disk_probe.asm` is a small DOS shell for real-hardware disk diagnosis.
It is assembled with NASM `-f bin` and inserted into a new copy of a user-supplied
system D88 using `scripts/d88_file.py`; see `HARDWARE_TESTING.md`. No BIOS, DOS
or game data is included in the tests. A DOS-reported successful log write is
not proof that the core has persisted it to the host D88.

The full CPU test is `tests/run-cpu.sh`. It assembles `ao486_smoke.asm` with NASM
and runs the imported ao486 CPU/cache sources, including the documented local
cache changes, with the PC-98 CPU wrapper and
Intel RAM models. It checks a 486-only instruction (`BSWAP`), unaligned DWORD
memory and odd-port I/O, `REP MOVSD`, A20 wrapping and unmapped-memory isolation,
high reset-ROM aliases, interrupt/IRET, and a CPU-only reset that retains RAM.
The upstream simulation observer is supplied as a read-only test hook.

`CPU_REP_COUNTS=1 bash tests/run-cpu.sh` additionally exercises zero/one
repeated-string counts, partial CL/CH updates, 16/32-bit address sizes and
counts crossing the low-word boundary. `tests/prove-ecx-count-flags.py` proves
the registered count predicates against the actual register update logic
and all outputs of the original string unit; see
[the timing change and evidence](../rtl/cpu/STRING_COUNTS.md).

`run-upper-cache.sh` tests optional instruction caching at 80000hÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ9FFFFh
with actual ao486 execution and the synthesized VHDL cache policy. It covers
native self-modification, bank aliases, DMA, remapping/restoration and ROM
bypass, with negative controls for each external invalidation source and a
cached/uncached loop measurement. Use `Dockerfile.mixed` for this test, as the PowerShell runner now does by
default; the older `Dockerfile` image lacks GHDL Verilog export. `run-cache-map.sh` separately
compares the policy against the real PC-98 memory mapper with the option off
and on. See [the cache design and hardware benchmark](../rtl/cpu/UPPER_RAM_CACHE.md).

`run-extmem.sh` uses the actual CPU in protected mode with the optional 16 MB
and 64 MB DDR maps. It checks boundaries, the reserved 15ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ16 MB aperture,
partial/unaligned writes, copies between conventional and extended RAM,
instruction execution from DDR, and persistence through CPU-only reset.
The standalone bridge test also checks all byte masks/64-bit word lanes,
backpressure and a late read response across reset. These tests model DDR;
they do not establish real DDR operation or BIOS/XMS memory detection.
`hardware/ram_probe.asm` is the disposable DOS-disk RAM diagnostic. It writes
distinct sentinels at both ends of every mapped extended-memory MB before
checking them, to detect address aliasing. It also checks partial/unaligned
writes and returns from protected mode to save `Z98RAM.TXT` through DOS.
The CPU simulation exercises the same mode-switch and memory-test body from
a relocated COM segment, substituting a result port for DOS file operations.
A 64 MB diagnostic must reject the 16 MB model. The probe is destructive to
extended RAM and must boot without XMS/EMS managers or resident applications.

`run-memory-init.sh` runs the DOS driver's actual strategy/interrupt entry
points with 0/16/64 MB. It checks BIOS memory counts, restored nonzero RAM
contents, real-mode/A20 restoration, a caller stack outside the driver segment,
and unsupported device commands. `hardware/xms_probe.asm` then exercises the
real HIMEMX(98) API on a DOS boot disk: detection, free-space query, allocation,
lock/address/unlock, patterned round trips at both ends and release. The 64 MB
test requires a 17 MB block above the PC-98 aperture. It writes `Z98XMS.TXT`.
The separate [XMS timing probe](hardware/XMS_BENCH.md) compares single allocation,
16 KB growth, and checked XMS-to-XMS copies using hardware-calendar seconds.
Its source/protocol tests are prepared but not yet qualified; keep that status
distinct from the completed XMS correctness tests above.
`python tests/test_d88_raw.py` checks preservation of D88 headers and original
data, rejects boot-sector/size changes, and verifies no-overwrite CLI behavior.

`run-sdram.sh` exercises the actual SDRAM controller CPU port at 20/40/50 MHz.
Each run checks 384 requests on the SDRAM command pins: row/column/bank,
single/four-plane reads and writes, byte/plane masks, completion counts and
read-modify-write data that changes after the read command. A small constant
read-burst source supplies data; this is not a SDRAM electrical timing model.
The controller now uses the request's registered address/bank/masks, while
keeping graphics RMW write data live. Arbitration with other ports and FPGA
timing require separate validation.

Icarus 11 propagates pull defaults from some Intel model input ports into
connected Verilog registers. The test script inserts identity expressions at
those connections in temporary simulation copies. Vendored and synthesized
sources are not altered by the simulation workaround. These tests use actual CPU execution but not the
complete PC-98 peripherals, real BIOS or floppy images.

`run-cache.sh` uses the real instruction cache and Intel RAM models to test
warm hits, level-held/repeated invalidation, a request queued during tag clearing,
and invalidation during an outstanding burst. A full CPU program then runs with
cache off and on: it checks externally modified warmed code, CPU self-modifying
code, uncacheable upper-window code, and ALU/VRAM-copy checksums. The synthetic
bus uses eight added wait cycles by default (`+wait=N` overrides it). It prints
cycles and bus transfers for two small hot loops; these are diagnostic
microbenchmarks, not Rusty frame rates or a model of complete SDRAM arbitration.
A negative control disconnects invalidation and must fail on stale code.

It now compares instruction/low-memory cache settings 00, 10 and 11. The
optional conventional-RAM cache has a standalone `run-lowmem-cache.sh` test
covering all 4096 entries, tag collisions, byte-write invalidation, uncached
accesses, delayed ACK release, reset and invalidation during hits/misses.
Removing write invalidation must fail. `LOWMEM_CACHE=1` also enables the cache
in `run-cpu.sh` and `run-extmem.sh`; see `rtl/cpu/LOWMEM_CACHE.md`.

`run-cache-map.sh` combines the actual memory mapper with the production cache
policy. It checks 4,197,632 mapping cases for each upper-cache option, plus
control and DMA ownership cases; see `rtl/cpu/UPPER_RAM_CACHE.md`.
The DMA grant test separately checks requesting an already idle bus,
waiting for an active CPU transfer, retaining ownership and release/reset.

`hardware/cpu_bench.asm` assembles with NASM's `cpu 8086` restriction and runs
on a disposable System-disk copy. It synchronizes to a DOS-clock transition,
executes ALU and RAM-copy blocks until at least ten reported seconds elapse,
checks their results, and writes `Z98PERF.TXT`. Each block has 131,072 iterations.
Compare blocks per reported second using the same BIOS/settings. The clock may
have coarse resolution despite expressing its result in hundredths; this is
a synthetic throughput test, not a game frame-rate test.

`hardware/glyph_expand_probe.asm` captures synthetic odd-address lookup and
SHL/RCL pixel expansion at 70000h and 90000h. The independent checker is
`scripts/verify_glyph_expand_probe.py`; `python tests/test_glyph_expand_probe.py`
checks its golden capture and rejection of corrupt or malformed results.
See `rtl/cpu/GLYPH_ARITHMETIC.md` for the disposable-disk and memory requirements.

`run-font-tail.sh` connects the actual font loader and tail RAM. It checks
26,624 loaded bytes on both CPU and pixel ports, out-of-range write isolation,
and custom-character writes. A limited-storage negative control must fail.
Only the existing 2 KiB dual-port primitive is modeled; see `rtl/FONT_ADDRESS.md`.

`run-text-pixel-memory.sh` checks rendered Latin and two-cell Kanji pixels,
colors, reverse and underline with synchronous pixel-clock text/font memories.
It sweeps 0/12/25 ns RAM delay and rejects a 200 ns late-data negative control.

`run-graphics-address.sh` verifies two full graphics frames at seven partition
lengths and four repeat settings, including high length bits, 14-bit address
wrap and no SDRAM requests during vertical blank. It reproduced the original
backwards-counter bug before correction; the existing video/SDRAM test still
checks six clock phases and intentionally rejects late data.

## Native-aspect scaling and FM interrupt regressions

`run-video-scale.sh` includes measured-raster native fit, integer fit and integer
zoom with HDMI-only cropping. Full-frame pixel-coordinate checks cover CE stalls,
400/480-line and 320x200/320x240 sources, mode changes and small-output fallback.
`floppy_overlay_tb` also verifies that the caption stays inside a cropped viewport.

`run-opna-timer.sh` instantiates the real OPNA register/timer logic, leaving audio
synthesis components unbound. It checks timer A/B flags, one-cycle clears at every
sound-enable phase and repeat IRQ assertion for dividers 2/4/5/6. The inherited
source loses the first timer-B clear at phase zero with divider two. This is an
interrupt regression, not a test of generated audio waveforms. `OPNA_SOURCE` can
select a prior source file. The default run also reintroduces the enable-gated
clear in a temporary copy and requires the regression to reject it. Selective
clears preserve the other pending timer, and reset must release IRQ without a
software status read.

`hardware/fm_timer_probe.asm` checks 100 consecutive timer-B IRQ12 deliveries,
flag assertion/clearing and cascaded PIC EOI, with the 86-board FM/PSG muted.
It writes `Z98FM.TXT` on a disposable boot disk and does not measure audio quality.

`run-opna-jt08.sh` uses `zet98-video-sim:latest` to test PC88's JT08 YM2608
implementation at 75 and 100 MHz. It covers all six stereo FM channels, three
PSG voices, six rhythm ROM instruments, sample rate, chip ID, PSG/GPIO reads,
timer IRQ/clear and one write per held CPU transaction. Synchronized control
instances check LFO/SSG-envelope waveform changes; a deliberately disabled LFO
must fail. See `rtl/OPNA_JT08.md` for source provenance and board limitations.

`hardware/rusty_sound_probe.asm` wraps the user's locally supplied 193-byte
`ONGCHK.COM`, preserving its detection procedure byte-for-byte. The original
entry jump is redirected to a harness that calls the same procedure and saves
its exit code to `Z98SND.TXT`; code 3 indicates an 86 board with extended OPNA.
The private game binary is not included in the repository. Run on a disposable
DOS carrier; this checks game detection, not the waveform or soundtrack choice.

## Compressed activity overlay and CRTC reset

`tests/run-floppy-overlay.sh` compares every pixel of all 59 animation frames
with the uncompressed reference, checks frame wrap, caption dots and drive
selection, then checks 56576 continuous/bursty-CE pixels for three-clock
RGB/sync/blanking alignment. The ROM packer independently reconstructs all
165200 original pixels before writing its two ROM files.

`tests/run-crtc-reset.sh` exercises the complete CRTC text path after six
reset phases, including stopped-clock recovery and settings changed during
reset. It checks a 640-pixel rendered line after each release. Temporary
copies rename the legacy VMODE identifier so VHDL-2008 can compile the
original expression port mappings; no logic changes are made by the runner.

`tests/run-decode-buffer-proof.sh` proves arbitrary-state output/next-state
equivalence against the original ao486 buffer with Yosys, including three
negative controls. Use the installed `zet98-formal-tests:latest` image through
`scripts/test.ps1 -AdaptersOnly -SimulationImage zet98-formal-tests:latest
-TestScript tests/run-decode-buffer-proof.sh`. The mixed simulator image runs
`tests/run-decode-buffer-cpu.sh`: 262144 buffer-input combinations, sequential
histories, and both cached and uncached real-CPU instruction/REP tests.

`tests/run-sdram-control-cdc.sh` checks operation-type routing on all four
CPU/drawing/floppy SDRAM clients with 15 ns delay and 5 ns required setup.
Six source rates and four memory phases exercise 18432 CPU/drawing commands
and 12288 continuous floppy requests. Four late-operation and two bypassed
completion-synchronizer mutations must fail. See `rtl/cpu/SDRAM_CONTROL_CDC.md`
for the two source-clock completion waits and required hardware comparison.

`tests/run-write-reset-proof.sh` uses the formal image above to prove all five
pipeline reset outputs against `reference/write_reset_legacy.vh`, plus temporal
induction over the actual command and predecode register updates. Wrong-selector
and missing-flush mutations must fail. See `rtl/cpu/WRITE_RESET_DECODE.md`.
`tests/run-write-payload.sh` runs string-write payload equivalence and both
cached and uncached CPU regressions in the mixed simulator image.

`tests/run-turbo-cdc.sh` runs the 100 MHz system-clock transfer tests against
100 MHz SDRAM and 75 MHz video. It exercises CPU/sub-CPU and floppy read/write
bundles, operation/completion control, video transfers/settings/status and
video measurement. Routing-delay assertions and intentionally broken controls
remain enabled; the constituent rate sweeps accept `CPU_RATES` for a focused run.

`tests/run-clock-rates.sh` checks FM/PIT/VFO at 40/50/60/75/90/100 MHz, rejects the
old integer FM divider at 75 MHz, and checks PCM formats, FIFO/IRQ behavior and
all eight sample rates at 20/40/50/60/75/90/100 MHz. These are functional simulations;
they do not establish routed FPGA timing or audible playback quality.

`tests/run-segment-fault-proof.sh` proves all seven outputs of the optimized
read-segment checker against its frozen prior implementation, with arbitrary
descriptors, addresses, lengths and selector combinations. Wrong stack priority
and limit-boundary mutations must fail. `tests/run-read-segment.sh` also runs
4,637,520 directed/random comparisons against the original upstream behavior.

`tests/run-write-finish-proof.sh` proves the early write-completion selectors
against the original decoder and checks their actual register-update invariant
by induction, including null-command flushes with retained substeps. Wrong
selectors and missing flushes must fail. Both new proof scripts use the formal
image; run the mixed-simulator CPU and protected-memory suites after RTL edits.

`tests/run-segment-length-proof.sh` proves the segment-only size decoder against
the actual command decoder for all inputs, conditional only on a virtual
segment check being active. A wrong byte-size mutation must fail. Run this in
`zet98-formal-tests:latest` after editing either length expression.

`tests/run-execute-descriptor-proof.sh` proves the execute stage's actual
speculative descriptor payloads match the original decoder whenever their
unchanged write enables assert. All decoder inputs are unconstrained. Wrong
stack/second-descriptor sources must fail; the cached-limit register invariant
and its negative controls also run. See `rtl/cpu/EXECUTE_DESCRIPTOR_PAYLOAD.md`.

The decode-buffer proof now uses Intel's actual Cyclone V cell model for the
explicit ready mux. Run `scripts/test.ps1 -SimulationImage zet98-formal-tests:latest
-TestScript tests/run-decode-buffer-proof.sh -StartOnly` **without** `-AdaptersOnly`
to copy/hash the vendor models from the installed Quartus image.
`tests/run-fpga-ready-mux.sh` runs the hardware-model boundary/history test and
focused CPU regressions; the ordinary portable buffer test remains exhaustive.

System-address selection: `tests/run-system-address-proof.sh` proves the parallel mux against the preserved priority decoder for all inputs and task-address states, with a wrong-selector negative control. Use the formal image and `-AdaptersOnly`.

`tests/run-write-control-proof.sh` proves early write-stage RF and stack-width
selectors against their frozen original decoder, then checks actual pipeline
register updates by induction. Wrong selector, missing flush, and incorrect
simultaneous load/retire priority must fail. Use the formal image and
`-AdaptersOnly`; run `tests/run-write-payload.sh` separately in the mixed image
for cached/uncached CPU, interrupts, reset, and REP regressions.

`tests/run-tlb-linear-proof.sh` proves exact TLB address update and hold
behavior for arbitrary state, payload, flush, alignment-fault, and request
combinations, followed by actual register-update induction and five negative
controls. Use the formal image with `-AdaptersOnly`, then run CPU and
protected-memory tests in the mixed simulator image.

`tests/run-ascal-poly-prepare.sh` uses the mixed image to synthesize the actual
scaler sum/clamp VHDL with GHDL and analyze the complete scaler. Export its
`build/ascal-poly-proof` directory, copy it into the formal-image container at
the same path, and run `tests/run-ascal-poly-proof.sh`. It proves all input
pairs against the original arithmetic and rejects three deliberate faults.

The decode-buffer proof and boundary/history test also check `dec_fetch_fits`
against the original capacity comparison, including the equal-capacity case.
`tests/run-write-parameter-proof.sh` proves task-switch global-parameter
payloads at every enabled update and arbitrary global mux priority/hold state,
with wrong-data and wrong-substep negative controls. Use the formal image
with `-AdaptersOnly` for the parameter proof; the decoder proof needs the
actual Intel atom models and therefore omits that switch.

`hardware/fat12_decode_probe.asm` is a read-only DOS shell for isolating CPU
errors in FAT12 cluster decoding. Assemble with NASM `-f bin`, then run
`python tests/fat12_decode_probe_unicorn.py <binary>` using Unicorn. The
preflight checks the synthetic table and six positive/injected-error cases.
On hardware it scans 1,198 entries 32 times and prints PASS or FAIL without
saving a file. A failure leaves its cluster index on debug I/O port 7FF0h.
This is an isolation probe, not a replacement for DOS save tests or the
whole-image audit in `verify_floppy_file.py`.


`run-boot-media.sh` checks media-triggered BIOS release, mount/load ordering,
reset, eject behavior and the empty-boot override. It renders all four prompt
pages through `video_output.sv`; `verify_boot_prompt.py` compares every pixel
against the expected text and placement, then checks handoff to native video.
`ide_bootrom_unicorn.py` exercises the actual assembled option ROM and resident
service, including optional owner-BIOS discovery and a private image IPL.
See `software/DISK_BIOS.md` for invocation and supported image layouts.


`run-z486-upper-policy.sh` uses the mixed simulator image to check all bank
mappings and synthesize the actual VHDL policy. Export `build/z486-upper-policy`
and copy it to the same path in a z486 simulator snapshot before running
`run-z486-upper-cache.sh`. The latter exercises the actual CPU with upper
instruction caching off/on, self-modification, bank aliases/remaps, DMA,
ROM bypass and a loop checksum; three disconnected-flush negative controls
must fail. `run-z486.sh` also covers upper data bypass and in-flight fills.

`run-opna-jt08.sh` covers 75, 90 and 100 MHz host clocks. Its PSG sample-bus
check performs rapid adjacent-register writes and volume readback, rejects
PSG-triggered FM busy periods, and verifies that FM busy protection remains.
This models the busy-poll/register-0A write sequence used by Rusty's PDR
sample driver; full-game pitch still needs a hardware comparison.

`run-opna-psg-negative.sh` restores the old PSG busy and stretched-strobe
behaviours independently; the rapid sample/readback checks must reject both.

`run-pit-clock.sh` checks the actual PIT clock generator plus PTC8253 mode 3
using Rusty's PDR divisor 154. Across 20/50/75/90/100 MHz hosts it requires
24,576 input strobes and 159-160 sample interrupts per 10 ms. It also checks
reset and rejects the old SFTCLK sel=1 configuration (12,500 strobes and 81
interrupts at 90 MHz). The fractional generator targets 2.4576 MHz, matching
the machine's port-42h timer-family indication.

`hardware/grcg_bulk_probe.asm` writes patterned full video planes with plain
and GRCG bulk string operations, then saves spatial samples from both pages
to a fresh diagnostic floppy. Assemble with NASM `-f bin`; run
`grcg_bulk_unicorn.py <probe.com>` for the reference and corrupted-output
negative control. `scripts/verify_grcg_bulk_probe.py <Z98BLK.BIN>` checks a
hardware capture. Audit the entire result disk before accepting a pass.

`hardware/dos_file_crc_probe.asm` computes CRC32 for `*.?ZH` through DOS file
reads from B: and writes a new `A:\Z98FCRC.BIN`. Use private disposable media
and a separate writable boot/result floppy. `dos_file_crc_unicorn.py <probe.com>` tests
empty, odd-length, non-ASCII-name and larger-than-64-KiB inputs against zlib,
including a corrupted-output negative control. Verify hardware output with
`scripts/verify_dos_file_crc_probe.py <capture> <expected.json>`; the expected
manifest contains raw DOS names as `name_hex`, `size`, and `crc32`.


`run-text-semigraphics.sh` exercises production KNJSCR with all 256 2x4
patterns, 8/16-line cells, 40/80 columns and synchronous memory delays.
It covers ordinary line/font and Kanji precedence, decorations, blink,
cursor and live mode changes. Forcing the old attribute interpretation
must fail blank code 0 / F1. `run-crtc-reset.sh` also checks the ATRSEL
parent/pixel stages across reset phases. Snapshot mapping, transport and
SDC endpoint guard tests include the 122nd bit carrying this mode.

`run-z486-unreal-cs.sh` runs the actual z486 through PC98 bridges and checks
all four visible CS low-bit values across CR0 mode changes, CPL0 privileged
instructions before CS reload, and a protected far transfer from an odd
real-mode segment. It needs no firmware or game assets.
`run-z486-xms-resident.sh` additionally accepts the private initialized
HIMEMX fixture at test-assets/himemx-resident.bin and checks copy/resize,
19KB data integrity and unchanged driver code. Do not publish that snapshot.

`run-z486-rmw-reload.sh` runs Watcom C 9.x loop tails (`inc dword [ebp-0Ch]`,
`mov eax,[abs]`, `add eax,[ebp-20h]`, `mov edx,[ebp-0Ch]`, `cmp edx,[eax]`)
3,600 times through the actual z486 and PC98 bridges, with frames in cached
low RAM and in DDR and with calls, stack stores and DDR misses in the body.
A register count must match both the memory count and the table limit. Before
the load-WB ordering fix it failed on the first pass: the older MOV's pending
memory token overwrote the ADD result in the same cycle (the cause of original
PC-98 Doom's `W_CacheLumpNum: 19781`). Unicorn passes the same binary.
`run-z486-rmw-trace.sh` builds the same test with a 512-cycle data-path ring
buffer printed on failure. Both need no firmware or game assets.

`run-z486-fuzz.sh` is a differential integer fuzzer. `z486_fuzz_gen.py`
generates Watcom C 9.x-style blocks (dependent register chains, EAX bias,
absolute/frame/indexed memory in cached low RAM, uncached upper RAM and DDR,
frame read-modify-writes, shifts, IMUL, MOVSX/MOVZX, SETcc/ADC after flag
definitions) and logs all GPRs after each block. The testbench dumps
40000h-9FFFFh (`+dump=`); `z486_fuzz_compare.py` runs the same binary on
Unicorn and reports the first differing block. `SEEDS`, `BLOCKS`, `BLOCK_LEN`
and `FUZZ_OUT` select the run. It caught the B161 write-order bug in all six
calibration seeds, then two further bugs that B163 still had. With the B164
data-unit/VIPT fixes, seeds 1-30 (360,000 instructions) match Unicorn.
`z486_fuzz_minimize.py` delta-debugs a failing block pair against a compiled
testbench in a running container; `+trace_lo=`/`+trace_hi=` with `RMW_TRACE`
print a data-path ring buffer for that EIP window. Unicorn runs on the host.

`run-z486-regression-batch.sh` runs the retained z486 suites and reports
every result instead of stopping at the first failure.
`run-z486-flat-regression.sh` belongs to the unfinished flat-admission
candidate: it refuses to run once `z486.sv` no longer matches its pinned base.

`run-z486-stack-allocation.sh` checks 80 protected-mode stack-availability
and allocation comparisons through the actual z486 and PC98 bridges. Cases
cover signed widths, four-byte alignment, both sides of the unsigned size
comparison, the measured B149 stack values, and low/extended RAM. It uses
no firmware or game assets. Use the Verilator-equipped CPU simulation image.

`tests/run-pegc-control.sh` checks the standalone PEGC mode/MMIO/banked/linear
address front end and 8-bit palette write events, including a truncated-index
negative. `tests/run-pegc-palette.sh` checks RGB888 dual-clock RAM across CPU
rates/phases, concurrent independent accesses and a truncated-lookup negative.
`tests/pegc_palette_synthesis.qsf` checks actual Cyclone V RAM inference. These
modules are now part of the opt-in packed display path; see `rtl/graphics/PEGC.md`.

`run-pegc-ddr.sh` checks CPU framebuffer halfwords/byte masks and three-client
arbitration, gapped read bursts, fairness, command stability and reset draining.
`run-pegc-line.sh` uses the production arbiter with continuous CPU traffic and
the actual 160-pixel leading blank at 90/100 MHz. It checks all 640 pixels, wrap,
late completion, underruns, reset with stopped pixel clock, two-edge local reset
release and held-payload delay. Three negative controls reject stale publication,
late payload and direct unsynchronized reset release.
`pegc_line_synthesis.qsf` checks real RAM inference.

`run-pegc-bus.sh` joins control, palette and framebuffer with full physical
address and memory/I/O qualifiers. It checks both linear aliases/all banks,
palette read/write, byte masks, reset and repeated ACK side effects. Its negative
must reject repeated palette writes. `run-z486-pegc.sh` runs the independently
authored `hardware/pegc_cpu_probe.asm` through the actual z486, CPU wrapper,
bridges, PEGC target and DDR arbiter, then repeats the protected-stack regression
through the same enabled path. No firmware/game assets are used. PEGC remains
disabled by default; the full candidate uses the `-PackedGraphics` build switch.

`run-pegc-raster.sh` tests12,800 rows of production GDC packed addressing, both
page sizes, partition/repeat behavior and wrong-SAD-units rejection, then the
actual line reader. `run-crtc-pegc.sh` tests the production CRTC's exact640-pixel
RGB888 alignment, text overlay and reset; an intentional one-pixel RGB shift
must fail. It also runs existing text/reset and128-bit settings transport tests.
`run-pegc-display.sh` connects actual CPU bus writes, DDR arbitration, line RAM
and palette, checks both linear aliases, byte masks, wraps and concurrent writes,
and rejects a truncated palette. `test_pegc_constraints.py` checks the new held
command's bounded setup/hold scope, exact reset-chain asynchronous-input scope
and missing-endpoint guards; only the proven SAD/pitch alignment constants may
disappear during synthesis. Functional reset fanout retains timing checks.

`hardware/pegc_display_probe.asm` is a self-authored DOS hardware diagnostic:
262,144 banked framebuffer bytes, independent two-dimensional pattern, RGB888
palette and explicit 640x400 GDC geometry. Assemble with NASM `-f bin`.
`-DBIOS9821` instead requests extended BIOS mode BH=11h and leaves GDC geometry
untouched, to separate initialization from scanout. It is a deliberate BIOS
control, not proof of a game's exact protected-mode BIOS parameters.
`verify_pegc_display_probe.py program.com [--bios9821]` executes the program in
Unicorn, verifies every byte against an independent formula, checks palette and
port/BIOS sequences, and rejects injected readback corruption. BIOS services are
modeled in this verifier; their actual implementation needs hardware testing.
Hardware runs use new disposable disks and a saved `Z98PGC.TXT` with a full disk
integrity audit. The private DOS disk and any firmware are not part of the test
source and must not be published.

For hardware isolation, `-DBIOS9821 -DPITCH_ONLY` adds only PITCH40 after the
BIOS setup. `-DBIOS9821 -DSTAGED` waits for a key between BIOS-only, pitch,
repetition, partition, clock and enable controls, printing GDC status at each
stage. Use matching verifier flags `--bios9821 --pitch-only` or
`--bios9821 --staged`. These are diagnostics, not game fixes.

### Graphics GDC parameter RAM

`tests/run-gdc-pram.sh` exercises the production GRAGDC command FIFO and decoder
with a registered-read-address model of its M9K FIFO. It checks all16 PRAM start
addresses and bounded writes (no display alias or wrap after address15), actual
line-drawing pattern bits on the VRAM bus, a moved-pointer hardware reset and
400 decoded PEGC raster addresses. Six write/ACK latency combinations and an
old-alias negative control are required to pass. Production RTL has explicit
reset initialization; the positive test needs no power-up source transformation.
The historical baseline reproduction used only a model-side RFIFOADDR zero
initializer to match FPGA power-up, without modifying its decoder.

The revised floppy overlay also verifies all boot-font caption pixels, the
16-pixel upward offset and background passthrough. Negative controls restore
the old position, black background or reversed font bits and must fail.

### Keyboard request during interrupt service

`run-kbconv-pic-eoi.sh` connects production KBCONV and z8259 using the byte adapter and mapping models from the keyboard transport test. Across five EOI delays and one/four-cycle acknowledgement, it checks queued make/break, extended arrows, modifiers and typematic, IRR clearing at acknowledge and stable vectors. The baseline loses the next keyboard edge at EOI; the corrected PIC preserves it. Production wire receiver coverage remains in `run-kbconv-backpressure.sh`. This integration regression does not by itself establish the cause of a particular game failure.
