# Experimental PC-98 ATA read service

`pc98_ide_read_bios.inc` implements the read side of a PC-98 INT 1Bh disk
service on the core's raw ATA master. It is **not yet an installable option
ROM or a hard-disk boot implementation**. The existing D0000h disk-ROM window
still returns FFFFh in the FPGA. Initialization/boot entry points, ROM discovery,
mount/geometry discovery, writes and complete DOS compatibility remain work
in progress.

The embedding 386-or-later program supplies `bios_previous_vector`, a far
pointer to the previous INT 1Bh handler, and the constants `BIOS_HEADS`,
`BIOS_SECTORS` and `BIOS_CYLINDERS`. Geometry must match the image, independently
of the ATA controller's CHS translation. The private DOS game disk uses
8162 cylinders, 8 heads and 17 sectors of 512 bytes. Transfers to ATA use LBA.
The caller must provide at least 600 bytes of free stack below SP; the service
uses a stack bounce buffer and requires no writable ROM storage.

Implemented behavior:

- AL=80h: drive-zero CHS, with a zero-based sector in DL; AL=00h: 24-bit DL:CX
  linear sector addressing. Other devices chain to the prior handler.
- AH low nibble 6: read BX bytes to ES:BP; BX=0 means 65536 bytes. Partial
  final sectors are copied without overwriting the next byte. Segment-offset
  crossings are normalized; buffers extending past physical 1 MB are rejected.
- AH low nibble 1: verify by reading, without modifying the caller's buffer.
- AH=84h: return the configured 512-byte geometry, after checking ready status.
  Initialization updates only drive zero's disk-equipment bit. An absent/busy
  device is not advertised as ready.
- Write returns PC-98 status 70h (not writable); format/unsupported commands
  return 40h. Bounds failures return D0h, following the NP2kai IDE convention.
  ATA errors/timeouts currently return 60h; detailed ATA error mapping and
  retry policy remain incomplete.

The routine preserves registers, including their upper halves, and caller
flags other than the documented AH/CF results and geometry outputs. It polls
PIO with ATA interrupts disabled and acknowledges the ATA status before
re-enabling interrupts. This is not an asynchronous disk driver, and it cannot
share the channel with another active ATA driver. No write/format command is
issued by the service.

## Verification

`tests/run-ide-bios.sh` executes the service on the actual ao486 RTL with an
ATA port model. Its default smoke test passes seven sector commands and
12277 legacy-bus transfers, checking geometry, CHS cylinder rollover, linear
addressing, a partial sector, segment crossings, register/DF preservation,
VERIFY, device chaining, missing media, timeout and ATA error handling.

An optional `BIOS_FULL_TRANSFER=1` run includes a complete 64 KB transfer; it
is much slower under Icarus. The independent Unicorn 2.1.4 test passes all
135 sector commands, including byte-for-byte comparison of the 64 KB result:

```sh
nasm -f bin tests/pc98_ide_bios.asm -o build/ide-bios-test.bin
python tests/pc98_ide_bios_unicorn.py build/ide-bios-test.bin
```

`tests/hardware/ide_bios_probe.asm` is a separate read-only probe for the
owner's private prepared VHD. It temporarily hooks INT 1Bh, checks geometry,
IPL/partition checksums, a CHS boundary and a 64 KB linear read, restores the
old handler, then saves Z98HDRO.TXT on its disposable floppy. It does not boot
the hard disk. On the Native50 FPGA build it passes all checks against the
prepared 568336384-byte VHD, including the full 64 KB read. The VHD was only
read; the diagnostic result was saved to its separate disposable floppy.

## Calling-convention references

- NEC, *PC-9800 Series Technical Data Book, BIOS*, printed pages 277–288,
  especially the read/verify register tables and relative-sector addressing:
  [technical manual](https://pc98.ne.jp/devdocs/pc-9800technicaldatabookbios.pdf).
- [NP2kai `bios/sxsibios.c`](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/bios/sxsibios.c),
  for later IDE geometry sense and byte-count conventions.
