# EGC test oracle


Unmodified shift functions and types extracted from NP2kai commit `5939e0c6d5985c4c08fc70f289a83290e5d3e6f7`.

Upstream: https://github.com/AZO234/NP2kai/tree/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7

`np2-egc-shift.inc` contains the tables/shift routines before `EGCOPE_SHIFTB`;
`np2-egc-types.inc` contains the EGC type definitions. Platform typedefs and
the driver live in `../egc_shift_reference.c`.

`np2-egc-write.inc` contains the subsequent operation macros, raster functions,
operation table, `egc_opeb` and `egc_opew`, ending before `egc_readbyte`.
`../egc_write_reference.c` supplies a small four-word destination array and
reproduces the pre-write pattern load, mask and plane selection performed by
upstream `egc_writeword`. It emits deterministic inputs and expected results
for the RTL operand selector. Source files preserve the original code except
for whitespace normalization. No CPU, ROM or game is included. Both upstream
license notices are retained.

The oracle describes reference-emulator behavior for native aligned 16-bit source transfers. It is cross-checked against an independent pixel-list model. It does not establish undocumented byte-access or register-write behavior on a physical PC-98.


Original file SHA256:

- `mem/memegc.c`: `3e53d0ff0d1a4eed057c3a110aa8524d886a6acfa601831b07a2d3c59c8eb0e2`

- `io/egc.h`: `f388a39302dfc182876eefceb56cbedce9adf50571d964517bd024ee8049bbd0`

- `LICENSES/LICENSE.TXT`: `a04bf1e94f34b951261e7a80c04f03f74df25046671a986d070f5be44be422c1`

- `LICENSE`: `ec422b02511463156e7d06c89f8c8b05d1a1c12c8ea961e2c4ac5b91e4b27c51`
