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

`bash tests/run-font-address.sh` exercises the actual controller and converter
through CPU port writes: 8,192 ANK row/half addresses and all 282,624 bytes in
the 92-row glyph area, including all three ROM banks. It independently
restores each original defect in temporary source copies and requires the
corresponding printable-character check to fail. All checks pass after the
fixes. Existing pixel-clock text/font tests also pass all six delay/cursor
combinations and reject deliberately late RAM data. These tests prove address
selection and the tested display pipeline, not complete game compatibility.

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
and a truncated record are rejected. Hardware capture remains pending.

For a standalone diagnostic floppy, assemble with `-DPROBE_SHELL=1` and set
`SHELL=Z98FONT.COM` in its minimal CONFIG.SYS. That version flushes its result
and halts with interrupts enabled rather than returning from DOS's shell.
The DOS 3.30 D88 boot produced the same 1,528-byte capture as the DOS 6.20
hard-disk run in NP2kai. Keep source images unchanged and use a new copy for
each hardware capture because an existing result filename is refused.
