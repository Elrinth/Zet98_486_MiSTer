# Combined font rendering capture

`tests/hardware/font_pipeline_probe.asm` exercises the font-read, upper-RAM,
glyph-expansion and graphics-write sequence together. It uses synthetic code
and a generated pixel-doubling table; no game or ROM data is distributed.

Assemble with NASM, `-f bin -DPROBE_SHELL=1`, and install as the shell of a
disposable DOS floppy. Use native memory banking without memory managers.
The program refuses to proceed unless its code segment is at most 5000h and
DOS has allocated conventional RAM through A0000h. It modifies graphics RAM
and enables 16-colour access; reset after the test. It restores the CPU
graphics page and disables GRCG before saving. The result file `Z98PIPE.BIN`
must not already exist: exclusive creation prevents overwriting an earlier
capture.

The same position-independent kernel runs in segments 7000h and 8BDEh, with
interrupts both disabled and enabled. For each of fourteen menu characters it:

- Reads sixteen rows through alternating left/right CG-ROM port accesses.
- Stores the bytes in upper RAM, then expands them using an odd-address word
  lookup table and shifts each complete row through four byte carry operations.
- Retains the intentional overlap between the original glyph buffer and the
  later shifted output, while recording each stage before it is overwritten.
- Draws a black shadow and white foreground through GRCG RMW, with odd-address
  word writes and duplicated scanlines, then reads all four graphics planes.

Each plane starts with a different nonzero pattern. The capture includes the
untouched byte on either side of the draw and the extra shadow scanline, so
incorrect clearing, plane selection, row stepping and boundary writes remain
observable. This is 56 records and 53,312 checked payload bytes.

Verify the returned file using:

```text
python scripts/verify_font_pipeline_probe.py Z98PIPE.BIN boot.rom
```

The verifier independently expands pixel strings, shifts a complete 32-bit
row and applies shadow/foreground masks to its expected plane image. It also
checks allocation bounds, record order, metadata, dimensions and exact length.

## Measured results, 2026-09-22

NP2kai and the SuperStation One running FullFont50 both pass all 53,312 bytes.
Their entire 53,664-byte captures are identical, SHA-256
`4a9fc74caafd3826607bbfe7c841e51eb451932d01c9c7cf7b2aded608ce70ae`.
The hardware RBF hash is
`41009f06741fbe4a28746725b85eb66b2fb889c3619693b76057a28ae9537f97`;
the combined owner ROM hash is
`647b5fa95a1a55096728829b74d4729e45adfd49d8e3a86aabf486a042f21db7`.
The retrieved hardware D88 hash is
`5ade80fc9f6e103f3d5cf5e85ec4908dd5fe8cd48354cf7b9dbc7f0e29580953`.

A separate verifier audit flipped the first and last byte of each stage in
every record: all 784 single-byte mutations were detected as exactly one
mismatch. Ten malformed header, allocation, record-metadata and length cases
were rejected. Private captures and audit logs remain outside version control.

These results verify this combined rendering sequence. They do not verify
the game's character conversion, live input arguments, complete game state,
frame rate or sound. Rusty's malformed title-menu text remained present on
the same FullFont50 build; a live-game capture is the next diagnostic step.
