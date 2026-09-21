# Experimental extended RAM

Build with `./scripts/build.ps1 -Cpu ao486 -ExtendedRamMB 16` or `64`.
The default remains zero until hardware and BIOS/driver validation are complete.
These values describe the top of the physical address map, not free DOS memory.

The original SDRAM memory map, ROM, video RAM and floppy buffers remain in place.
CPU memory addresses from 1 MB to the selected limit go through a separate
16-bit-to-64-bit DDR bridge. The 15–16 MB PC-98 system/graphics aperture is
reserved and currently returns all ones; its aliases are not implemented.
Thus a 16 MB map supplies 14 MB of extended RAM and a 64 MB map supplies 62 MB,
in addition to existing low memory. A20 masking remains upstream of this map.

The DDR byte address is `0x30000000 + guest_physical_address`, following the
core-owned region used by the MiSTer ao486 reference. No request can escape the
selected guest range. Commands hold through DDR backpressure, use byte enables
for all four 16-bit lanes, and drain an outstanding read across a soft reset.
CPU-only F0 reset retains RAM. Extended memory bypasses the CPU's instruction
cache. A new one-word DDR read buffer reuses each fetched 64-bit word across
nearby reads; accepted byte writes update resident data. Reset invalidates it.
Only the CPU currently writes this region; a future external DMA writer must
invalidate or update this buffer. It is not a general CPU data cache.

`tests/run-extmem.sh` executes the actual ao486 in protected mode for both
sizes: byte/word/unaligned DWORD writes, boundary and aperture isolation,
`REP MOVSD` in both directions, code execution from DDR and RAM retention
through CPU reset. Both configurations pass, with 372 and 402 DDR commands
before read buffering and 208 and 224 with it. These are transaction counts,
not measured throughput. Buffer on/off bridge tests explicitly verify four
successive halfwords need one DDR read instead of four, and a negative control
with byte-write updates removed must fail on stale data.
The bridge test separately checks all byte masks/word lanes, stalls and a
late read response across reset. Quartus analysis/elaboration passes for the
16 MB integration. The pre-buffer 16 MB / 40 MHz build fits at 32,826 ALMs,
395 RAM blocks and 63 DSP blocks; it still fails full-design timing. Its
disposable DOS probe passes on the SuperStation, checking sentinels at both
ends of every mapped MB, partial writes and protected-to-real-mode return.
The 64 MB / 40 MHz build also passes the same physical-memory probe on hardware,
checking 62 mapped MB of extended RAM. It fits at 32,917 ALMs with the same
RAM/DSP use and also fails full-design timing. The new read buffer's fitting
and hardware check remain pending. Neither hardware probe establishes BIOS/XMS
memory discovery or exhaustive RAM stability.

The supplied old PC-98 BIOS does not automatically know about this extension.
Do not report 16/64 MB as usable in DOS until BIOS memory-size fields and an
appropriate PC-98 XMS driver have been verified. Reference behavior includes
the count in 128 KB units at BIOS work address 0401h and memory above 16 MB at
0594h. Merely writing those fields is not a substitute for RAM and driver tests.

Reference behavior (not copied code):

- [NP2kai BIOS memory reporting](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/bios/bios.c)
- [NP2kai physical memory map](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/i386c/cpumem.c)
- [MiSTer ao486 DDR interface](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/ao486.sv)
