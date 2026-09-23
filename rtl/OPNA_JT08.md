# PC-9801-86 with PC88's JT08 OPNA implementation

Select with `scripts/build.ps1 -OpnaBackend JT08 -SoundBoard PC9801_86`.
The default `Legacy` backend remains available for comparison and recovery.
The board target is YM2608 OPNA plus the separate PC-9801-86 PCM FIFO/DAC.
It is not YM2203 OPN, YM2612 OPN2, or the YM2610 Neo Geo configuration.

Build the tested #115 configuration with:

```powershell
./scripts/build.ps1 -Cpu ao486 -SystemClockMHz 100 -ExtendedRamMB 64 -SoundBoard PC9801_86 -OpnaBackend JT08 -LowMemoryCache -LowMemoryCacheKB 8 -UpperRamICache -RawIde -MidiUart -BuildCpus 8 -BuildMemoryGB 8 -StartOnly
```

## Source and integration

The user identified the JT12-derived JT08 implementation in
[PC88_MiSTer](https://github.com/MiSTer-devel/PC88_MiSTer/blob/master/rtl/sound/jt12/hdl/jt08.v).
The file history identifies yosinda as the author who added the JT08 wrapper
on 2024-05-23 (commit `98e2cfc3ce836b0189692efba40a5647458db2bb`), and later
added ADPCM-A, read strobes and widened PSG output. This is a PC88 adaptation
of Jotego JT12, rather than an unexplained file in upstream JT12.

`rtl/vendor/jt08/UPSTREAM.json` pins commit
`73a620ac1fe13628e3c41afa494d54c6484202f0`, the imported directories, local
patches, and the decoded rhythm ROM hash. JT12 and JT49 license notices remain
with their sources. The upstream MIF is preserved; `rhythm.hex` contains the
same 8192 bytes for a portable inferred ROM.

JT08 supplies all six FM channels, three PSG channels, six rhythm instruments,
OPNA register/status/identification, GPIO and timers. The old OPNA module is
elaborated only for the legacy backend. The board's `pcm86.sv`, port-A460
extended-port gating, FM mute and shared IRQ12 routing remain in the top level.
As with a stock PC-9801-86, no external OPNA ADPCM sample RAM is connected; this
is not a SpeakBoard configuration.

`opna_jt08.sv` runs the sound engine with a 7.9872 MHz fractional clock enable,
independent of the CPU frequency. It keeps the core in reset for 512 master
enables to initialize all time-multiplexed operator registers. The native busy
signal is exposed through two vendor module ports. The adapter uses it to
wait before a new sound write, asserts `OPN_WAITn` only for the selected sound
transaction, and commits each held CPU strobe once. Registered reads receive
four settling cycles before acknowledgement. No unbounded command queue or
CPU-speed-dependent software delay is needed.

The second vendor patch moves the full-width operator-result declarations
before generate blocks; otherwise Icarus can create a one-bit local implicit
wire at the accumulator input. FM/PSG/rhythm synthesis algorithms are unchanged.

The existing board mixer receives signed FM+rhythm output and the unsigned
12-bit PSG sum scaled into positive 16-bit range. Its FM/speaker/PCM mixer
topology is unchanged. Analog output filtering and gain calibration against
a physical PC-9801-86 remain unverified. A successful integration is not a
claim of perfect chip or board equivalence; upstream also documents incomplete
behavior, including ignoring register 29's SCH bit and fixed default prescaling.

## Verification

Use `tests/run-opna-jt08.sh` with `zet98-video-sim:latest` (Verilator).
It verifies at 75 and 100 MHz:

* OPNA chip ID `01`, extended status, PSG register readback and joystick GPIO.
* Timer-B IRQ assertion/status and clearing with short writes.
* Exactly one native write per held IO transaction, with bounded acknowledgement.
* Each of six FM channels separately on left and right; no opposite-side leakage.
* FM sample rate 7.9872 MHz / 144, each PSG voice, and each rhythm ROM instrument.
* Waveform differences from LFO and SSG envelopes against a synchronized control
  instance. A build with LFO deliberately disabled must fail that check.

Run `tests/run-opna-timer.sh` separately in the GHDL mixed simulation image to
protect the untouched legacy backend. Those tests pass too. Waveform simulation
cannot establish which soundtrack Rusty selects or whether its final mix
matches a real board.

Build #115 (`quartus-20260923-025821-a15bd7`) compiles at 100 MHz with 64 MB,
8 KB conventional-memory cache, upper-RAM instruction cache, raw IDE and MIDI
UART. The complete fitted design uses 36,010/41,910 ALMs, 461/553 M10Ks and
42/112 DSP blocks. Against legacy build #113, total utilization changes by
+320 ALMs, -14 M10Ks and -24 DSP blocks. Placement affects whole-design ALM
packing; the JT08 instance itself uses 1,343 ALMs, 12 M10Ks and 5 DSP blocks.
The fitted rhythm ROM contains 8,192 bytes.

Four of 212 reported timing checks are negative: CPU setup -5.783/-5.629 ns
(hot/cold), HDMI setup -0.708/-1.173 ns. This is within the user's experimental
-12 ns limit, not timing closure. The fitted pixel global-clock network and
HPS SPI/I2C/UART checks pass. The full database and reports are preserved.

On the actual SuperStation One/MiSTer hardware, #115 passes the CPU benchmark
checksums (429 ALU / 191 RAM-copy / 163 stack blocks per ten DOS seconds),
64 MB physical-map probe, and 100 FM timer-B IRQ12 deliveries with status
clearing and PIC acknowledgement. Rusty's original 193-byte `ONGCHK.COM`
detection procedure, wrapped without changing its procedure bytes, returns
code 3 (PC-9801-86 / OPNA) on both legacy #113 and JT08 #115. Thus the old
core's sound issue is not explained by this detector rejecting its OPNA.
This does not prove soundtrack selection or audible fidelity. Raw returned
diagnostic disks were unmounted, synchronized, downloaded and SHA-256 checked;
results and screenshots are in `build/hardware/jt08-opna/manifest.json`.
Rusty's animated opening and intact title menu run on #115; Enter advances
the opening. The user listened to the intro and reports much better music,
with substantially improved, authentic-sounding drums. Speech just after the
C-LAB screen still sounds unusual; the user requested leaving that issue for
later. Its cause is not established. No calibrated comparison with a physical
sound card or sustained gameplay frame-rate measurement has been performed.

Rusty's supplied launcher probes OPNA identification via `ONGCHK.COM`, and
the game supplies both `.M` and `.M2` music plus PMD/PMDB2 drivers. This is a
useful game-level distinction to check for the reported OPN-like sound.
