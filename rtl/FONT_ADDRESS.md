# Font address mapping

Rusty's English menu reads characters through CG-ROM row `09`: a reference
trace records 2,616,320 reads of 14 glyphs (space and the letters in Start,
Continue, Options), with no direct ANK reads. The old `knjaddrcnv` branch for
rows `09..0b` uses an incorrect base and row stride. For example, A1=`53`,
A3=`09`, A5=`20` selects FONT.ROM offset `1e60` instead of `7e60`. In the
owner's hardware font, the former contains a bracket-shaped pattern and
the latter contains the requested S.

The mapper now applies the existing 96-glyph row calculation to `09..0b`
as well. The independently checked layout is `0x1800` bytes of ANK data,
followed by 92 rows of 96 glyphs, each containing 16 left-half bytes and 16
right-half bytes. The reference loader is NP2kai `font/fontv98.c`,
`v98knjcpy`, at revision `5939e0c6d5985c4c08fc70f289a83290e5d3e6f7`.

## Independent ANK selector defect

The CPU writes character selection through ports A1/A3 and the glyph row
and half through A5, then reads glyph data through A9. `knjaddrcnv` uses a
zero high byte to select the ANK font region at `0x0800 + character * 16`.
Its high bit selects a left/right half only for a Kanji glyph.

Previously, `KNJRAMCONT` unconditionally put inverted A5 bit 5 into that
high bit. An ANK read with A5 bit 5 clear therefore ceased to be ANK and
selected unrelated font data. The controller now leaves ANK's high byte
zero and retains the original half-selector construction for Kanji.

The PC-98 reference is NP2kai `io/cgrom.c`, `cgrom_oa1`, `cgrom_oa3`,
`cgrom_oa5`, and `cgrom_ia9`, inspected at revision
`5939e0c6d5985c4c08fc70f289a83290e5d3e6f7`. Its ANK read branch does not add
the Kanji left/right offset. This change does not implement all CG-ROM
semantics: reserved character ranges, blank upper ANK rows, and writable
gaiji restrictions require separate verification.

## Verification

The loader also stopped after the first 256 KiB of the 288,768-byte font and
could select only banks 0 and 1. The final 26,624 bytes, including the last
stored JIS rows, never reached bank 2. It now uses a full-width bounds check
and derives bank/address from the offset inside FONT.ROM. Writes outside
that exact region are blocked, including when an unrelated CPU write is
present during loading. The production top level supplies 20 loader address
bits, sufficient for the entire combined boot image.

`bash tests/run-font-address.sh` exercises the actual controller and converter
through CPU port writes: 8,192 ANK row/half addresses and all 282,624 bytes in
the 92-row glyph area, including all three ROM banks. It independently
restores each original defect in temporary source copies and requires the
corresponding printable-character check to fail. All checks pass after the
fixes. Existing pixel-clock text/font tests also pass all six delay/cursor
combinations and reject deliberately late RAM data. These tests prove address
selection and the tested display pipeline, not complete game compatibility.
The loader regression covers both sides of each bank boundary, first and last
font bytes, out-of-range writes, and the write strobe; restoring its old
two-bank limit fails the independent negative control.

Rusty's title menu has malformed lettering on the PaletteCaption50 FPGA
build while the same private game disk displays readable Start, Continue,
and Options text in NP2kai. Injecting the original row mapper into the emulator
also corrupts those menu letters, but does not exactly reproduce the FPGA's
glyph shapes; further differences remain possible. Hardware verification
with the corrected mapper remains pending.

## DOS byte-capture probe

Assemble `tests/hardware/font_probe.asm` with `nasm -f bin` as `Z98FONT.COM`.
Run it from a disposable DOS image. It creates `Z98FONT.BIN` only if that
name is absent, reads 23 selected character codes, and records 736 pairs of
immediate and delayed CG-ROM reads. It writes no glyph data or font ROM.
The included cases cover Rusty's row-09 letters, ANK, adjacent JIS rows,
and the last stored JIS row.

After unloading the image, extract its result and run:

```
python scripts/verify_font_probe.py Z98FONT.BIN path/to/the/exact/boot.rom
```

The verifier checks the capture structure, compares each pair with the raw
font data, and separately reports unstable reads. It returns failure for any
byte mismatch. In NP2kai, all 736 pairs match the known-working development
ROM (`647b5fa9...42f21db7`), with zero unstable reads. A changed capture byte
and a truncated record are rejected. This reference result does not validate
the corrected hardware build.

For a standalone diagnostic floppy, assemble with `-DPROBE_SHELL=1` and set
`SHELL=Z98FONT.COM` in its minimal CONFIG.SYS. That version flushes its result
and halts with interrupts enabled rather than returning from DOS's shell.
The DOS 3.30 D88 boot produced the same 1,528-byte capture as the DOS 6.20
hard-disk run in NP2kai. Keep source images unchanged and use a new copy for
each hardware capture because an existing result filename is refused.

GDCGuard50 hardware completed the floppy probe at 23:58:23 on 2026-09-21.
After unloading it, the captured file reports 395 mismatching sample pairs
out of 736, with zero immediate/delayed disagreements. Every returned byte
matches the original mapper plus an unfilled third bank. In particular,
the two halves of row-09 S exactly match original offsets `1e60`/`1e70`.
This confirms the source defects on hardware; it does not yet validate the
corrected RBF. Capture SHA-256:
`ce6941ff44c359a35702751b7e39288552282c4d32c51cd6a7152c2c0eff507c`.

FontMap50 (`971ace7`, built before the third-bank loader fix) passed all
sixteen reported timing-corner categories, minimum +0.095 ns, and the
SPI/I2C/UART fitted-pin guards. On hardware on 2026-09-22, the same probe
reduces mismatches from 395 to 29 of 736 sample pairs, with zero unstable
reads. The remaining mismatches are the absent third-bank glyph `535c`;
the tested ANK and row-09 letters now match the working ROM. Capture SHA-256:
`52d0641706aa921a9c579b10adae27f05b176ce74e3e005034ec91e393431eb0`.
The loader change alone still needs verification through the actual RAM path;
see the later UpperCache50 result below.
Rusty's title menu remains malformed on this build despite correct sampled
font bytes. The mapper fixes are therefore necessary but not sufficient to
establish correct game text rendering; the subsequent drawing path remains
under investigation.

The optional `-DIMMEDIATE_IO=1` probe uses adjacent immediate-port OUT/IN
instructions, including Rusty's font-access mode selection. It preserves
the normal capture format and immediate/delayed read pairs. Its reference
capture matches all 736 pairs, while FontMap50 hardware produces exactly
the same capture as the DX-port probe (29 third-bank mismatches, no unstable
reads). The tighter OUT/IN sequence alone therefore does not explain the
remaining menu corruption. This does not cover the game's subsequent RAM
lookups, font expansion or graphics writes.

## Third-bank storage coverage

UpperCache50 (source 0939a06, containing the widened loader) still produces
the same 29 mismatches, all in glyph 535Ch, with zero unstable reads. Its
hardware capture is byte-identical to FontMap50. Tracing the storage path
finds that `GAIJIRAMDP` only stores offsets 1400h..2BFFh, the 6 KiB custom
character window, and returns zero elsewhere. The controller test had checked
the addresses and strobes but had not instantiated this storage module.

`GAIJIRAMDP` now covers the complete 6800h-byte third-bank tail using thirteen
existing 2 KiB dual-port primitives. This adds 20 KiB of storage. Addresses
outside the tail remain disconnected instead of aliasing stored bytes. The
original custom-character window remains within the writable tail.

`bash tests/run-font-tail.sh` connects the production loader/mapper to the
production tail RAM with a synchronous model of only the 2 KiB primitive.
It loads all 26,624 bytes, reads them through the pixel port, attempts writes
at all 104,448 out-of-range addresses and rechecks every stored byte, then
reads all tail bytes through the CPU font ports. Both ends of the original
custom-character window also pass CPU-write/pixel-read checks. Restoring the
limited storage decode fails at offset zero. All these checks and the
existing full font-address suite pass. Physical fitting and a new hardware
font capture remain required; this is not yet a verified hardware fix.

The separate glyph arithmetic probe also passes all 4,096 checked bytes on
UpperCache50; see `cpu/GLYPH_ARITHMETIC.md`. Rusty's malformed title-menu text
still needs investigation beyond these isolated checks.

## Zero-extended word stores

The optional `-DWORD_READS=1` mode reads a row using adjacent immediate
OUT/IN instructions, clears AH, and executes STOSW, matching the sequence
used by the game's single-byte characters. Its `Z98FONTW` capture stores
the font byte followed by the expected zero high byte. The verifier checks
both independently and reports high-byte errors separately. This mode also
implies `IMMEDIATE_IO`; the original probe format remains unchanged.

`-DUPPER_CAPTURE=1` places the capture records in segment 9000h, then copies
them back for the DOS file write. It checks that the program is below 60000h
and its DOS allocation covers the upper buffer before accessing it. Use a
disposable shell without memory managers and native banking, as for the
conventional-RAM probe. This tests upper stores, not upper instruction fetches.

The combined word/upper mode passes all 736 samples in NP2kai, capture hash
`f070fbeef6c7c59f237e21cdbe4b19861589b154f0426994dd5a593f41f889c8`.
UpperCache50 hardware produces the same known 29 font-tail mismatches and
zero high-byte errors. Its capture hash is
`74385785106343baa4b331ed3f0e45cd7a7eb3a531533e9149e35e13606b215f`;
the retrieved D88 hash is
`38f66d0f0dc25d1f656a254414e0901dd17a740171891d1087ca75379c4ab578`.
Thus the tested IN-AL/XOR-AH/STOSW sequence introduces no additional errors.
It does not explain the remaining malformed menu on that build.

## FullFont50 hardware result

On 2026-09-22, the SuperStation One passes the same word/upper capture on
FullFont50: all 736 samples match, with zero high-byte errors. The 29 missing
535Ch bytes are now correct. The capture is byte-identical to the NP2kai
reference (`f070fbeef6c7c59f237e21cdbe4b19861589b154f0426994dd5a593f41f889c8`).
The retrieved disposable D88 hash is
`b3e7132ac03905441bf1257e4fab5547e3f12c7a9e409e904ffde7111a64e04c`.

The RBF uses RTL source e5aa389 at 50 MHz with 64 MiB extended RAM, the 8 KiB
low-memory cache, upper-RAM instruction caching, PC-9801-86 sound, raw IDE
and MIDI UART. Its SHA-256 is
`41009f06741fbe4a28746725b85eb66b2fb889c3619693b76057a28ae9537f97`.
The revised graphics-handshake constraint fff8cce passes all four operating
corners on that unchanged fitted database, minimum +0.082 ns; see
`GRAPHICS_TRANSFER.md`. The design uses 478/553 M10K blocks and 34,341/41,910
ALMs. The ROM hash is the same `647b5fa9...42f21db7` used for prior captures.

This confirms the representative hardware font reads including the previously
missing tail glyph. The simulation additionally covers every tail byte.
Neither result alone establishes complete Rusty rendering or game performance.

The same FullFont50 run subsequently booted the private DOS 6.20 VHD, showed
Rusty's intro scenes and reached its title screen after an intro-skip input.
The 03:27:20 hardware screenshot still shows malformed Start/Continue/Options
lettering. The font-tail repair therefore fixes the captured ROM defect but
does not resolve this separate game-rendering problem. Animation frame rate
and audible sound quality were not measured in this check.

The subsequent [combined font pipeline capture](cpu/FONT_PIPELINE.md) passes
all 53,312 payload bytes on FullFont50 and in NP2kai. It connects the font
reads, upper-RAM expansion and GRCG writes in one program; actual game
character selection remains outside its scope.

The title lettering was subsequently corrected on the same FullFont50 core
by fixing two conversion constants in the private English game's older GDC
driver. See the [separate driver result](../disk-templates/dos620/RUSTY_GDC_FONT.md).
This distinguishes that menu problem from the ROM-address and missing-tail
defects repaired in the core itself.
