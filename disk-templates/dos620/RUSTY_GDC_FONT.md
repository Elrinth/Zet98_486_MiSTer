# Rusty English: older graphics-driver font correction

The tested English package contains two graphics drivers. Its EGC driver
selects single-width ROM glyphs for the English title text, but its older
GDC driver retains the Japanese character-conversion constants. With that
driver, the input for the final `t` in `Start` selects a full-width `U`.
Doubling that glyph reproduces the previously malformed menu on FullFont50.

`scripts/patch_rusty_gdc_font.py` creates a corrected copy of the exact known
7,800-byte `GRPGDC.COM`. It changes two literal bytes in its compressed
stream, preserving the layout and matching the English conversion used by
the other driver. The input hash is
`cf69d2ad1d6eca07e6dfa13f4f21c03c488db44b4a4bbbc14f6faa50a23b0f99`;
the output hash is
`5a42d4f76bd0c87d1e8473cd503447501902f072a1ee781530e01caf7707aded`.
Other files are rejected. The original and any existing output are preserved.

```text
python scripts/patch_rusty_gdc_font.py /your/RustyEN/GRPGDC.COM /new/GRPGDC.COM
```

Install the new file only in a copy of this English game's directory, keeping
the original driver. No game data is distributed with the project. This is
a private-game compatibility correction, not an EGC implementation in the
core or a general patch for Japanese releases.

## Verification, 2026-09-22

A private NP2kai live-game trace captures the character argument, converted
code and raw ROM bytes for 80 glyphs. The existing EGC driver converts 8274h
to row/column 0974h. The older GDC driver converts it to 0355h. The corrected
GDC driver converts it to 0974h; all 2,560 captured font bytes then match
the intended ROM glyphs. The other tested letters and spaces also match.

The independent hardware pipeline diagnostic already passes its 53,312 bytes,
so this driver comparison tests a selection step outside that diagnostic.
A corresponding hardware live trace did not produce its result file and
was not used as proof of the driver behavior.

For the direct hardware comparison, only these two driver bytes changed
relative to the known working private DOS 6.20 game disk. No tracer was
installed. The core remained FullFont50, RBF SHA-256
`41009f06741fbe4a28746725b85eb66b2fb889c3619693b76057a28ae9537f97`.
The corrected test VHD, before boot, has SHA-256
`172a3a9f48eb9580d963dd906a406263358ea95c1a121fe56da2fddd1463859b`.

The SuperStation One boots the corrected copy and shows readable Start,
Continue and Options in all six title captures between 04:34:06 and 04:34:31.
Their white foreground masks match the reference at the original 640x400
coordinates: zero differing pixels across the three checked rectangles
(3,740, 5,440 and 5,400 pixels). This verifies the menu correction; cursor
animation, complete gameplay rendering, sound and frame rate need separate
checks. The original source game and existing test VHD were not modified.
