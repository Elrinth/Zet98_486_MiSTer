# Experimental PC-9801-86 playback

Select `-SoundBoard PC9801_86` in `scripts/build.ps1`. Default builds retain
the previous OPNA board pending hardware and game validation. This option
identifies as an 86 board at A460h and adds its PCM playback registers, while
retaining the existing OPNA FM/PSG implementation. No additional sound ROM is
distributed. The user's sound BIOS and game drivers still need validation.

The implementation has a 32 KB byte FIFO, signed 8/16-bit samples, left/right
mono and stereo routing, high-byte-first 16-bit samples, eight fractional sample
rates, full/empty status, FIFO reset, a programmable refill threshold and a
latched interrupt acknowledged through A468h. A46Ah selects either the sample
format or threshold according to control bit 5. Status bit 4 reports the pending
PCM interrupt. A466h selects PCM volume and A66Eh bit 0 mutes PCM.

PCM and OPNA interrupt requests are ORed onto the existing IRQ12 input (slave
PIC IR4, interrupt vector 14h with the usual PC-98 PIC setup). Clearing one
source does not clear the other. An ISR must check/service both sources before
EOI. OPNA extended-port enable and OPNA mute follow A460h bits 0 and 1. The
existing FM/speaker mixer gain is retained, with half-scale PCM added using
the existing saturating adder.

This is an initial playback implementation. Analog volume uses a linear
approximation; recording, external analog inputs and full mixer routing are
not implemented. Overflow writes are discarded and underflow holds the last
complete sample. Real-device behavior around threshold acknowledgement,
underflow and overflow needs game/driver comparison. No complete 86-board
compatibility or Rusty/Nightslave audio claim is made yet.

Simulation covers all six audible formats, signed sample ordering, the whole
32 KB FIFO, simultaneous refill/drain and wraparound, held writes, full/empty,
threshold/acknowledge/masking, reset and mute. Sample-rate counts match at
20/40/50 MHz. PIC tests independently verify shared FM/PCM interrupt levels;
they are not a mixed-language CPU/PCM/PIC or real-hardware test.

The 40 MHz / 64 MB build now passes the disposable DOS hardware probe on the
SuperStation: 86-board identification, the complete 32 KB FIFO's full/empty
states and reset, plus two IRQ12 deliveries with status, acknowledgement and
PIC EOI. It records the result in `Z98PCM.TXT`. PCM stays muted throughout;
audio output quality and game-driver compatibility remain unverified. The
build fits at 33,087 ALMs and 427 RAM blocks but still fails full-design timing.

Behavioral references (not copied source):

- [NP2kai register implementation](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/cbus/pcm86io.c)
- [NP2kai sample formats](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/sound/pcm86g.c)
- [Original FreeBSD(98)/Linux98 driver](https://lkml.indiana.edu/hypermail/linux/kernel/0210.3/1103.html)
- [MAME register map and playback](https://github.com/mamedev/mame/blob/master/src/devices/bus/pc98_cbus/pc9801_86.cpp)
