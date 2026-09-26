# Experimental MPU-PC98II UART interface

Build with `scripts/build.ps1 -MidiUart` and select **MPU MIDI: UART** in
the core menu. The option is off by default. This prototype has passed
simulation, guest IRQ tests and exact HPS serial capture on a fitted 50 MHz
core. The first hardware test exposed an incorrect HPS UART placement; the
corrected build delivers the complete 134-byte diagnostic packet to ttyS1.
Game MIDI reception and FluidSynth activity were later verified on MidiPollFix50; TV audio quality remains unverified. It is not a complete intelligent-mode
MPU-401.

The first Nightslave hardware test with MPU enabled stalled in its MIDI driver;
the same RBF reaches the title with MPU disabled. This was corrected by the IRQ6 withdrawal change described below. A silent polling diagnostic reads FEh under
CLI, then observes a stale pending IRQ6 and an empty-input interrupt handler.
The driver compatibility issue is not covered by the earlier serial replay.
MidiPollFix50 subsequently passed the correction on hardware; see HARDWARE_TESTING.md, "MIDI withdrawal fix on hardware". The new 90 MHz z486 candidate still needs its own game trial.

The guest interface is the PC-98 default: low-byte data at **E0D0h**,
command/status at **E0D2h**, and **master PIC IRQ6**, normally vector 0Eh.
Odd bytes and IBM-PC 330h/331h ports do not select it. It does not share
PC-9801-86 sound IRQ12 or IDE IRQ9.

Supported protocol:

- FFh resets the queues/mode. Outside UART mode it returns FEh; when leaving
  UART mode it returns no acknowledgement, as Roland specifies on page 22 of
  its [technical reference](https://cdn.roland.com/assets/media/pdf/MPU-401_OM.pdf).
- 3Fh enters UART mode and returns FEh. Read it before sending MIDI data.
- Status bit 7 is one when no input/acknowledgement is available. Bit 6 is
  one when the transmit FIFO is full; software must wait before writing.
- Sixteen-byte transmit and receive queues preserve byte order. CPU reads
  hold their result for the complete read strobe. Multi-cycle writes enqueue
  exactly once. IRQ stays asserted while acknowledgement/input is pending;
  drain available bytes before EOI.
- 31,250 baud, eight data bits, no parity, one stop bit; raw channel data,
  running status, SysEx and real-time bytes are transported unchanged.
- Commands other than reset are ignored after entering UART mode. Before
  UART mode, commands other than FFh/3Fh are unimplemented and not acknowledged.
  Sequencing, track requests, direct-send commands and clock-to-host remain
  future work; do not select this option for drivers requiring those features.

`UART_TXD`/`UART_RXD` connect to MiSTer's HPS serial route. The configuration
string advertises 31250 baud and MIDI so Main can offer its existing MidiLink
menu. Local MUNT/FluidSynth or USB MIDI routing still needs a hardware test;
this module does not itself synthesize audio. An external DIN MIDI module
requires a suitable USB MIDI interface or another supported MIDI transport,
not a direct cable to the FPGA GPIO pins.

This is original RTL. Port/IRQ and reset/UART protocol were checked against
[NP2kai mpu98ii.c](https://github.com/AZO234/NP2kai/blob/5939e0c/cbus/mpu98ii.c)
and its default `mpuopt=82h` configuration. MiSTer routing was checked against
[ao486's UART wrapper](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/rtl/soc/uart/uart.v)
and [Main's UART/MidiLink handling](https://github.com/MiSTer-devel/Main_MiSTer/blob/master/user_io.cpp).
No emulator implementation code was copied.

## Verification

The PIC now permits withdrawal of master IRQ6 before acknowledgement when
the MPU's last byte is polled away. The request remains edge-triggered: a
held-high input does not retrigger after EOI. This is configured only for
IRQ6, preserving legacy pulse producers such as `mouseint`. It is not a full
8259 rewrite; legacy default/spurious-vector handling remains separate work.
`tests/run-pic.sh` checks polling, sixteen withdrawal delays, reassertion,
mask/unmask, EOI, existing pulse sources, and simultaneous MIDI/sound. Its
negative control restores the original retained request and must fail.

The MPU tests separately reject the former UART-reset acknowledgement.
The DOS serial diagnostic is now v2: it explicitly leaves UART mode without
expecting FEh between the 100 acknowledged reset/UART pairs. Its independent
model rejects a fabricated UART-reset ACK as well as missing IRQ, wrong ACK
and stuck-busy failures. Earlier hardware results below used v1 and describe
the old prototype behavior; they do not verify this correction.

`tests/run-mpu-uart.sh` uses Verilator from `tests/Dockerfile.video`. At each
of 20/40/50/60/90/100 MHz it independently decodes 137 transmitted bytes and
checks backpressure, FIFO wrap/overflow, UART reception, invalid framing,
reset, disable, command acknowledgements, wrong addresses and byte lanes.
A deliberately broken held-write guard must fail. These are peripheral
simulations, not evidence that the full core can run at those frequencies.

`tests/run-disk-interface.sh` also exercises the real wrapper and HPS option
command: bit 26 enables MPU, a decoded byte reaches UART_TXD at 31250 baud,
ACK IRQ reaches the machine input, and MPU accesses do not select IDE.
The actual VHDL bus expressions pass low-byte/CPU priority tests, and the
existing PIC simulation checks 32 IRQ6/EOI cycles plus simultaneous MIDI and
cascaded sound interrupts. Hardware game/driver compatibility is pending.

A private trace of the owner's Nightslave copy in NP2kai uses commands
3Fh, FFh and 3Fh, then UART data. Its final 6335-byte UART session passes an
independent serial-decoder replay against this RTL at 50 MHz, without loss,
reordering or FIFO overflow. This establishes compatibility with that observed
command sequence, not audible playback on the FPGA. The trace and game data
are not distributed in this repository.

The silent `tests/hardware/mpu_uart_probe.asm` diagnostic is prepared for a
disposable DOS boot disk. It checks 100 reset/UART pairs (200 IRQ6 ACKs),
restores the prior PIC mask/vector, and queues an exact 134-byte SysEx packet
for independent HPS serial capture. Its saved `Z98MPU.TXT` result covers
command IRQs and successful enqueueing, not the physical serial stream.
`tests/mpu_probe_unicorn.py` checks that program's normal flow and missing-IRQ,
wrong-ACK and stuck-busy failures against an independent x86/DOS/MPU model.
On 2026-09-21, the MIDI50 build passed all 200 ACK/IRQ6 checks on the
SuperStation One and saved the expected result. Independent Linux capture
received zero bytes. The fitted atom database shows the UART at
`HPSINTERFACEPERIPHERALUART_X52_Y66_N111` (UART0), whereas MiSTer's MIDI
route requires `HPSINTERFACEPERIPHERALUART_X52_Y67_N111` (UART1/ttyS1).
This legacy project includes sys.qip without sourcing sys.tcl, so it lacked
the upstream location assignment. The project now explicitly fixes that
location, and MIDI builds check the actual
fitted netlist. The check rejects the observed wrong placement.

`tests/hardware/capture_mpu_uart.py` captures the diagnostic packet at
31250 baud without transmitting or starting a synthesizer. It refuses a
busy port, saves raw bytes and a JSON result, and restores the original
serial settings. Its Linux pseudo-terminal test checks fragmented delivery,
an incorrect packet and settings restoration.

The corrected UART1-50 build (5def4ed) was loaded at 19:25:07 on 2026-09-21.
All sixteen timing corner/type reports are nonnegative, minimum +0.074 ns;
board-I/O constraint coverage remains incomplete. The guest again passes
200 IRQ6 acknowledgements, and the independent HPS capture receives exactly
134 bytes at offset zero, matching the diagnostic byte for byte. Serial
settings are restored afterwards. Captured packet SHA-256:
`49a265aaedf5513a3b0d2c4a3ce3f4d90c26426a51b19d2b439c268c0427a38f`.
This verifies physical transport, not synthesis, external modules, intelligent
mode or music quality. The location guard has since been expanded to
`scripts/check-hps-peripherals.tcl`, also covering the shared SPI/HDMI routes.


The current #138/#139 debug builds do **not** enable this MPU interface.
Their 115200-baud CPU telemetry can become random notes if routed into
FluidSynth. Keep UART connection disabled on debug builds. The forthcoming
combined candidate uses `-MidiUart` without `-Z486DebugUart`.

For a MIDI-enabled build, set the core's **MPU MIDI: UART**, then MiSTer's UART
connection to **MIDI**, **Local**, **FSYNTH**, at **31250 baud**. The user's
MiSTer already has FluidSynth and GeneralUser-GS.sf2 installed. In Night Slave,
choose **MIDI (MPU/RS-232C)**. On build #142, the user confirmed both NightSlave music and its music-test
menu sound correct with this configuration. The independent 134-byte wire
diagnostic and 200 IRQ acknowledgements also passed. MUNT can emulate MT-32/CM-32 with owner-supplied
ROMs, but General MIDI music should use a suitable FluidSynth soundfont.


Reset handling: the MiSTer wrapper enables `RESET_PANIC`. A guest MPU reset,
core reset, or MIDI enable transition finishes any byte in flight, drops old
queued bytes, ends SysEx and sends CC64/120/123/121 zero on all16 channels.
New traffic follows this sequence using the existing FIFO backpressure.
This change is simulation-tested; the installed #142 RBF does not include it.

`scripts/mister_midi_guard.py` watches host core transitions and silences the
local FluidSynth through its control socket. It does not consume UART data
and only reacts when the previous core was Zet98. This also covers unloading
the FPGA, when the outgoing core can no longer transmit. The owner MiSTer
runs it via its new linux/user-startup.sh; a held note test went from1 voice
to0 on core exit. It requires FluidSynth's local port9800; it does not reset
external hardware modules or MUNT.
