# Experimental MPU-PC98II UART interface

Build with `scripts/build.ps1 -MidiUart` and select **MPU MIDI: UART** in
the core menu. The option is off by default. This prototype has passed
simulation; integrated FPGA timing, serial capture and audible playback are
not yet verified. It is not a complete intelligent-mode MPU-401.

The guest interface is the PC-98 default: low-byte data at **E0D0h**,
command/status at **E0D2h**, and **master PIC IRQ6**, normally vector 0Eh.
Odd bytes and IBM-PC 330h/331h ports do not select it. It does not share
PC-9801-86 sound IRQ12 or IDE IRQ9.

Supported protocol:

- FFh resets the queues/mode and returns FEh. Read the acknowledgement.
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

The silent `tests/hardware/mpu_uart_probe.asm` diagnostic is prepared for a
disposable DOS boot disk. It checks 100 reset/UART pairs (200 IRQ6 ACKs),
restores the prior PIC mask/vector, and queues an exact 134-byte SysEx packet
for independent HPS serial capture. Its saved `Z98MPU.TXT` result covers
command IRQs and successful enqueueing, not the physical serial stream.
`tests/mpu_probe_unicorn.py` checks that program's normal flow and missing-IRQ,
wrong-ACK and stuck-busy failures against an independent x86/DOS/MPU model.
Hardware execution is pending a fitted MIDI-enabled core.
