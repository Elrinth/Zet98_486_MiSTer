# Experimental PC-98 raw-image ATA controller

Build with `-RawIde` to replace unused SASI slot 2 with `IDE hard disk` (`.vhd`/`.img`).
The image is a flat array of 512-byte sectors, not a dynamic VHD/VHDX container.
The separate [INT 1Bh service and BIOS-first floppy](../../software/DISK_BIOS.md)
now boot the owner's prepared DOS 6.20 image on Native50/Bundle50. The
write-enabled Bundle50 setup also passes file persistence and all four FPGA
memory profiles. The stock test ROM still cannot boot ATA directly: the
resident loader, matching image geometry and user-supplied DOS are required.

`scripts/import_disk_image.py source.hdi output.vhd` removes a validated HDI
header when its logical sectors are 512 bytes and writes geometry metadata
beside the output. It refuses 256-byte SASI HDIs; combining pairs of their
sectors would change the guest's disk layout. Geometry-dependent boot still
requires the appropriate BIOS/controller integration. Direct HDI selection is
not yet implemented.

The same utility imports standard HDM/FDI and error-free NFD revision 0 disks
into D88, preserving sector order, payload, FM/MFM, deleted marks and write
protection. NFD revision 1/retry records and NFD error/protection records are
rejected explicitly. This is an import workflow; the current floppy selector
still reads D88. Use a new output filename, for example:
`python scripts/import_disk_image.py game.hdm game.d88`.

The private DOS 6.20 multi-game image uses the
[DOS configuration templates](../../disk-templates/dos620/README.md).
Its menu and Rusty's intro boot on FPGA; Nightslave reaches its title.
Doom II runs in NP2kai but currently produces corrupt FPGA graphics after
text initialization. The image itself is not included in this repository.

Ports follow the PC-98 layout: 0430h presence, 0432h channel selection,
0640h 16-bit data, 0642h..064Eh even-byte task-file registers, and 074Ch
alternate status/device control. The ATA interrupt reaches slave PIC IR1
(IRQ9). The high byte of an unrelated odd PC-98 port cannot issue a command.
Only channel 0/master is present; CHS uses 16 heads and 32 sectors per track.

Supported commands are IDENTIFY, read/write sectors (including multiple
sectors and count-zero=256), verify range, recalibrate, seek and flush without
a device write cache. Unsupported features/commands abort. There is no DMA,
ATAPI, packet CD/DVD or LBA48. The generic MiSTer sector interface has no
separate host-I/O error result, so VERIFY checks range rather than promising
physical media verification. The represented capacity is limited to LBA28.

The 512-byte buffer has synchronous CPU and HPS ports. CPU reset/SRST drains
an outstanding host transfer before allowing another command to reuse it.
Read-only, empty/partial images and out-of-range commands cannot write media.
Do not replace a mounted file during a pending host write: the host owns that
already-issued transaction. Floppy/NVRAM and IDE use independent LBA, mount,
ACK and buffer routes; the stock four-slot path remains when RawIde is off.

`tests/run-ide.sh` checks the task-file protocol, byte lanes, IDENTIFY,
two-sector writes, CHS head/cylinder rollover, 256-sector reads, IRQ9 source
mask/acknowledgement, absent devices, bounds, read-only and reset draining.
`tests/run-disk-interface.sh` tests the real HPS command parser and wrapper,
including an outstanding floppy request while an IDE read waits for service.
Both directions transfer and compare all 512 bytes.

The hardware diagnostic `tests/hardware/ide_probe.asm` runs from a disposable
floppy. It requires exactly a 1 MB raw image containing the literal
`Z98 IDE DIAGNOSTIC ONLY` followed by CR/LF at byte zero before issuing its
single write to sector 17. It then reads that sector back, verifies all 256
words and expects four IRQ9 deliveries. This diagnostic is not a disk BIOS.

Hardware verification on SuperStation One, 2026-09-21: the initial 50 MHz
controller build passed IDENTIFY, guarded sector write/read, the full 256-word
checksum and all four IRQ9 deliveries. A host-side comparison confirmed that
only sector 17 changed. RBF SHA-256:
`24ba511f10d5779908221cabdb8af3212bae358e65493cc21847544c496eac69`.
This build still had video timing violations; it is diagnostic evidence, not
a timing-clean release. The subsequent shared-write-port RAM optimization
passes simulation and infers 4096 block-RAM bits in Quartus. Later Native50
and Bundle50 builds include it and pass BIOS reads and DOS file persistence;
see [hardware evidence](../../HARDWARE_TESTING.md).

The [INT 1Bh service](../../software/DISK_BIOS.md) is read-only by default;
explicitly bounded writes are available for the private writable image. It
is loaded before DOS by a small D0 floppy, not installed in the disk-ROM
window. The normal game launcher no longer needs a diagnostic D1 floppy.

Importer checks on the owner's Metal Force HDM, Dungeon Buster FDI and Dark
Gaiden NFD-R0 preserve every payload byte. A 512-byte-sector Azusa HDI also
converts byte-for-byte to raw VHD plus geometry JSON. These are conversion
checks, not boot tests. Several sampled translation HDIs instead contain
256-byte SASI sectors and remain deliberately unsupported by this path.
