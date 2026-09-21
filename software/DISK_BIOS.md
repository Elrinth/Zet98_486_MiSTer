# Experimental PC-98 ATA disk service

`pc98_ide_read_bios.inc` implements PC-98 INT 1Bh reads and optional bounded
writes on the core's raw ATA master. It is **not yet an installable option
ROM**. A separate BIOS-first diagnostic floppy now boots the private DOS 6.20
VHD on Native50 and reaches its game menu and Rusty's illustrated intro.
The existing D0000h disk-ROM window still returns FFFFh in the FPGA. ROM
discovery, mount/geometry discovery and complete DOS compatibility
remain work in progress.

The embedding 386-or-later program supplies `bios_previous_vector`, a far
pointer to the previous INT 1Bh handler, and the constants `BIOS_HEADS`,
`BIOS_SECTORS` and `BIOS_CYLINDERS`. Geometry must match the image, independently
of the ATA controller's CHS translation. The private DOS game disk uses
8162 cylinders, 8 heads and 17 sectors of 512 bytes. Transfers to ATA use LBA.
The caller must provide at least 600 bytes of free stack below SP; the service
uses a stack bounce buffer and requires no writable ROM storage.
This requirement is unsuitable for directly hooking an arbitrary bootloader:
the supplied DOS partition IPL uses SS=0, SP=028Eh. The bootstrap wrapper
described below switches to a private stack before calling the service.

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
share the channel with another active ATA driver. Default builds issue no
write/format command. Formatting remains unsupported in all builds.

## Optional bounded writes

`BIOS_ALLOW_WRITES=1` enables AH=05h/85h with the same CHS/LBA, byte-count and
buffer conventions. Both `BIOS_WRITE_FIRST_LBA` and `BIOS_WRITE_LAST_LBA`
must explicitly define an inclusive window inside the configured image.
Out-of-window writes return AH=70h before any disk command. These compile-time
limits complement image identification; they do not identify a disk by themselves.

Full sectors use a stack bounce buffer and PIO OUTSW. A partial final sector
is read first, overlaid with only the requested bytes, then written back.
The service waits for completion with BSY and DRQ clear and checks ERR/DF
before reporting success. Caller registers and flags retain the read ABI.
The default bootloader remains read-only unless explicitly built with these
defines. Use a separate disposable image for write validation.

The independent Unicorn test covers 21 cases: full/partial writes, a 64 KB
transfer, CHS and linear addressing, a segment crossing, exact BIOS readback,
protected neighbors, bounds, device chaining, register/flag preservation,
absent/busy media, command and completion errors, stuck DRQ and device loss.
`BIOS_WRITE_TEST=1 tests/run-ide-bios.sh` also passes on the actual ao486 RTL:
three reads, three write commands (one rejected by the ATA model), 9952 bus
transfers, segmented OUTSW, readback and preserved partial-sector tail.
An intentionally broken version that skips write completion fails the
independent test with `write returned before completion`.
The default read-only RTL regression still passes seven reads / 12291 bus
transfers after factoring the task-file setup into a shared routine.

`tests/hardware/ide_write_probe.asm` additionally checks an exact 1 MB media
capacity and diagnostic signature before writing, with its BIOS window
restricted to sector 17. On Native50, loaded at 14:24:33 CEST on 2026-09-21,
it passes full and 31-byte partial writes/readback, CHS/LBA, and rejection of
neighboring sectors. The returned image differs only in sector 17, with the
exact expected pattern and unchanged tail. This establishes sector writes;
The next file-level test passes on Bundle50 with a separate writable game
VHD. `hdd_file_probe.asm` uses create-new semantics for `A:\Z98WRITE.BIN`,
writes 70,001 bytes, flushes/closes, reopens and verifies every byte and EOF.
The 14:46:08 hardware capture confirms PASS. `verify_hdd_file.py` independently
compares all 568,336,384 image bytes against the pristine staging archive:
only 140 sectors change, inside FAT/root metadata and the five new clusters.
Both FATs agree, every unrelated FAT/root entry is unchanged, and the
returned payload matches on the host. Individual games' save behavior and
power-loss recovery are not established by this diagnostic.

```sh
nasm -f bin tests/pc98_ide_write_bios.asm -o build/ide-write-test.bin
python tests/pc98_ide_write_unicorn.py build/ide-write-test.bin
BIOS_WRITE_TEST=1 bash tests/run-ide-bios.sh
```

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

## BIOS-first boot experiment

`tests/hardware/ide_bootsector.asm` reads our resident loader from sectors 2–5
of a new 1.23 MB floppy. `ide_bootstrap.asm`, built with `BIOS_BOOT=1`, installs
the read service before DOS has loaded, checks the private VHD's IPL/partition
checksum and enters its original IPL. Selected HDD calls use a private stack;
other devices retain the ROM handler and caller stack. IRQs remain disabled
inside the wrapper until it restores the original caller frame, including
IF/DF and the returned carry bit.

The resident area D8000–DFFFF is ordinary RAM in this core's current map. This
is a **core-specific experiment**, not a portable driver for physical PC-98s.
Do not enable an upper-memory manager that can overwrite it. The geometry
and checksum currently identify only the owner's prepared game disk. Writes
remain disabled, including profile changes and game saves.

```sh
nasm -f bin tests/hardware/ide_bootsector.asm -o build/VHDIPL.BIN
nasm -f bin -DBIOS_BOOT=1 tests/hardware/ide_bootstrap.asm -o build/VHDLOAD.BIN
python tests/ide_bootstrap_preflight.py build/VHDLOAD.BIN private-game.vhd --bootsector build/VHDIPL.BIN
python tests/build_ide_boot_disk.py build/VHDIPL.BIN build/VHDLOAD.BIN build/vhd-boot.d88
```

The packager refuses existing output files and embeds only our loader and
zero fill. `BIOS_TRACE=1` adds request diagnostics in text RAM. Unicorn 2.1.4
checks the floppy calling convention, resident handoff, IPL contents, ROM
pointer guards, corrupt-image rejection, tiny caller stack, IVT preservation,
and CF/IF/DF. Bypassing the private stack fails the IVT check. It does not
emulate the DOS kernel after the IPL handoff.

Native50 booted the private VHD menu at 13:36:28 CEST on 2026-09-21 with the
traced BIOS-first floppy. Rusty selected from that menu reached an illustrated
intro scene at 13:40:05. The original NEC HIMEM profile reported zero XMS;
the initializer/HIMEMX profile subsequently boots with DOS high and passes
the direct 17 MB XMS allocation/copy/free test. NEC MEM still shows zero XMS
with HIMEMX; see [memory setup](README.md). The older
COM-from-DOS bootstrap is retained as a diagnostic but is not the working
boot method: the old DOS interrupt hooks can outlive their overwritten code.

## Calling-convention references

- NEC, *PC-9800 Series Technical Data Book, BIOS*, printed pages 277–288,
  especially the read/verify register tables and relative-sector addressing:
  [technical manual](https://pc98.ne.jp/devdocs/pc-9800technicaldatabookbios.pdf).
- [NP2kai `bios/sxsibios.c`](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/bios/sxsibios.c),
  for later IDE geometry sense and byte-count conventions.
