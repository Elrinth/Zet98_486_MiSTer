# Experimental DOS memory setup

`Z98MEM.SYS` exposes the ao486 core's tested extended-RAM map to PC-98 DOS
memory managers. It is an initialization driver, not an XMS implementation.
Use only with this core's ao486 16/64 MB builds, before any memory manager.
It requires 386 instructions and must not be installed in the original Zet
build or on an original PC-98. BIOS/OS files are not included.

The initializer probes distinct words in every mapped MB, restoring all
original values afterward. It accepts the 14 MB or 62 MB extended-RAM layout,
skipping the 15–16 MB system aperture. It publishes the count below 16 MB at
0401h and the MB count above 16 MB at 0594h. It refuses to advertise a partially
working map or run after an installed XMS manager. Its strategy/interrupt
entry points pass actual-CPU simulation with 0/16/64 MB, including restored
A20/mode state and unchanged probe contents. This is a small map probe, not
an exhaustive stability test.

Use the **PC-98** build of [HIMEMX(98)](https://github.com/lpproj/himemx.nec),
not an IBM-PC HIMEM driver. Tested reference commit:
`5dad3f18835c0d028bb7c9e967c548aaf152b15e`. Its memory-map discovery supports
the PC-98 aperture, unlike some older HIMEM ports. It remains a separate
package under its own Artistic License; retain its license and source when
redistributing its executable.

On a disposable copy of the user's DOS 3.30D boot disk, the following driver
order passes hardware XMS tests with the 64 MB / 50 MHz core:

```ini
BUFFERS=8
DEVICE=Z98MEM.SYS
DEVICE=HIMEMX.EXE /TESTMEM:OFF
SHELL=BOOT.COM
```

Here `BOOT.COM` is our diagnostic, not a general game-menu shell. The test
finds 63424 KB free, allocates/locks 17 MB at physical 01000000h, copies
patterns to and from both ends, then unlocks/frees the allocation and checks
that free memory returns. This demonstrates usable XMS, not a complete
PC-9821 BIOS or EMS/UMB setup. The 16 MB / 40 MHz fallback also passes, with
14272 KB free and a 1 MB allocation at 00110000h. `/TESTMEM:OFF` skips HIMEMX's slow exhaustive
test; separate physical-memory probes were run first. Do not add `DOS=HIGH`,
EMM386, UMB exclusions or game-specific sound drivers without testing them
with the selected DOS version and game.

## Building

Build `software/Dockerfile` as `zet98-dos-tools`. Inside a container with the
repository mounted at `/project`:

```sh
nasm -f bin software/z98mem.asm -o build/hardware/Z98MEM.SYS
nasm -DTOP_MB=64 -f bin tests/hardware/xms_probe.asm -o build/hardware/Z98XMS.COM
```

The tested HIMEMX assembler is [JWasm](https://github.com/JWasm/JWasm), commit
`a5c4ea03cc0545a15d81a354251b5f534bef7a1b`. With both pinned source trees under
`references/JWasm` and `references/himemx.nec`:

```sh
make -C references/JWasm -f GccUnix.mak -j8
references/JWasm/GccUnixR/jwasm -nologo -mz -Sg -Sn -DNEC98 \
  -Fobuild/hardware/HIMEMX.EXE references/himemx.nec/source/himemx.asm
```

To edit a disposable DOS D88, `scripts/d88_raw.py extract` writes its sector
payloads to a new raw image. Use `mcopy -i image.raw` to add the drivers,
replace CONFIG.SYS and install the diagnostic as BOOT.COM. Then
`scripts/d88_raw.py repack original.d88 image.raw new-test.d88` preserves D88
headers and requires the original boot sector and geometry. Both commands
refuse existing output files. Keep the original disk unmodified. This workflow
does not implement a hard-disk controller or a bootable VHD.
