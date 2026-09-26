# Experimental PC-98 raw-image ATA controller

Build with `-RawIde` to replace unused SASI slot 2 with `IDE hard disk` (`.vhd`/`.img`).
The image is a flat array of 512-byte sectors, not a dynamic VHD/VHDX container.
The [native disk option ROM](../../software/DISK_BIOS.md) is included in new
`-RawIde` builds. It uses the system `boot.rom` to boot a supported PC-98 DOS
image without a helper floppy. Build #137R3 boots DOS 6.20 from raw VHD and
IMG on hardware; both pass 70,001-byte persistence and complete image audits.
Earlier builds through #136 use the separate
BIOS-first floppy. Do not mount that helper with the native ROM.

`scripts/import_disk_image.py source.hdi output.vhd` removes a validated HDI
header when its physical sectors are 512 bytes and writes geometry metadata
beside the output. It refuses 256-byte SASI HDIs; combining pairs of their
sectors would change the guest's disk layout. Geometry-dependent boot still
requires the appropriate BIOS/controller integration. Direct HDI selection is
available with the native image bridge described below.

The same utility imports standard HDM/FDI and error-free NFD revision 0 disks
into D88, preserving sector order, payload, FM/MFM, deleted marks and write
protection. NFD revision 1/retry records and NFD error/protection records are
rejected explicitly. This remains useful for writable D88 copies; native
HDM/FDI/NFD mounts are read-only. Use a new output filename, for example:
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

The reusable [INT 1Bh service](../../software/DISK_BIOS.md) is read-only by
default. The native ROM enables capacity-bounded writes after validating the
image geometry. Its D0000h ROM installs code and private stacks in reserved
D8000hâ€“DFFFFh RAM. The legacy floppy loader remains available for old RBFs.

Importer checks on the owner's Metal Force HDM, Dungeon Buster FDI and Dark
Gaiden NFD-R0 preserve every payload byte. A 512-byte-sector Azusa HDI also
converts byte-for-byte to raw VHD plus geometry JSON. These are conversion
checks, not boot tests. Several sampled translation HDIs instead contain
256-byte SASI sectors and remain deliberately unsupported by this path.


## Native image containers (candidate, hardware validation pending)

The MiSTer image bridge now validates headers before announcing mounted media.
FDD0/FDD1 accept D88, HDM, FDI and NFD. HDM supports standard 77x2x8x1024,
80x2x15x512, 80x2x18x512, 80x2x8x512, 80x2x9x512 and 40x2x8x512 images.
FDI supports those same regular geometries, with an arbitrary byte-aligned
header offset. NFD supports regular 77x2x8x1024 revision-0 images with a 68112-byte
header and normal MFM sectors. All four owner-supplied Burning Dragon Plus
NFD images pass this metadata validation. Revision 1, retries, deleted sectors,
CRC/error records and irregular layouts are rejected rather than flattened.

Native HDM/FDI/NFD mounts are **read-only**. Their virtual D88 view contains
write-protect metadata; the source images are never rewritten as D88.
Use `scripts/import_disk_image.py` to create a writable D88 copy when needed.
Existing D88 read/write/sync behavior is retained.

IDE accepts raw VHD/IMG and HDI with 512-byte sectors and a 512-byte-aligned
header. HDI reads and writes add the validated header-sector offset; capacity
excludes the header. Geometry product and exact file length are checked, and
256-byte SASI images are rejected. This is not support for dynamic VHD/VHDX.
The embedded boot ROM still requires a supported PC-98 disk/partition layout.

Detection uses validated header fields, not just filename extensions (MiSTer
passes size and block data, not the extension). Unsupported images remain
unmounted. Per-drive probes and cache fills never reach another drive's buffer.
Mount metadata is serialized onto the legacy engine's shared metadata bus.
`tests/run-native-images.sh` covers data, geometry, malformed images, header
preservation, read/write offsets and eject; `tests/run-disk-interface.sh`
checks the actual HPS wrapper, mount probes and concurrent floppy/IDE traffic.


Hardware qualification of build #142 found a host filename conflict: stock
MiSTer Main's user_io_file_mount passes every `.fdi` to its Spectrum x2trd
converter, which rejects PC-98 FDI before FPGA access. A byte-identical copy
with `.hdm` extension bypasses that converter and boots the Popful Mail intro.
The FPGA detects its FDI header; no image conversion is involved. Keep the
original file. Native `.fdi` names require a MiSTer Main fix. Popful Mail then
shows a separate graphics corruption; HDM Metal Force and NFD Burning Dragon
reach DOS, but none of these games is yet fully qualified. Popful Mail's raw
HDM control has the same stripes, and Metal Force's D88 control has the same
parameter error. These failures are not isolated to their native containers.

Xanadu and Lemmings HDIs use 1024-byte DOS logical sectors over 512-byte
physical sectors. The original option ROM rejected their BPBs. The revised
ROM also recognizes the older NEC BPB used by Lemmings; bounded volume-size
and invalid-layout regressions pass. Tested through a temporary loader on
#142, Lemmings reaches its intro and the user confirms Xanadu in-game.
The integrated #143R2 ROM revision still requires hardware qualification.
