# Full WAD read control

`wad_read_probe.asm` is a self-authored DOS COM program, with no game code.
It opens `A:\DOOM1\DOOM.WAD` read-only and creates `A:\WADREAD.BIN`
exclusively. An existing output is an error. It never writes the WAD.

The first pass reads the entire file in 32 KiB chunks. The second performs
the same reads and computes reflected IEEE CRC32, retaining a running CRC
at every chunk boundary. Both check exact read lengths and a final EOF.
The supported file range is 12 bytes through 32 MiB. On failure the output
can be empty or incomplete; only a successful host verification counts.

Time comes from PC-98 BIOS INT 1Ch/AH=00h hardware RTC. BCD/range validation,
a finite initial liveness check and midnight handling are included. Each
pass has a 120-second budget checked between calls. This cannot interrupt
a stuck DOS/BIOS call; the hardware launcher therefore also supplies an
independent 300-second host deadline, guarded by the exact core, launcher
and keyboard identity. It returns the probe to MENU on expiry.

The output is little-endian:

- 0: eight-byte signature `Z98READ1`.
- 8: file byte length (u32).
- 12: read-only pass whole RTC seconds (u32).
- 16: read-plus-CRC pass whole RTC seconds (u32).
- 20: complete-file CRC32 (u32).
- 24: chunk count (u32).
- 28: chunk size, 32768 (u32).
- 32–63: zero reserved bytes.
- 64 onward: one running CRC32 (u32) per chunk, including the final partial chunk.

`tests/wad_read_probe_unicorn.py` runs the assembled program using independent
synthetic bytes, DOS calls and a mocked RTC. It checks data against Python's
zlib, exact/partial chunk boundaries, one MiB with segment-boundary crossings,
incoming DF, midnight, error paths, clock failure, timeout and corrupted reads.
`scripts/verify_wad_read_probe.py` checks every recorded CRC against a retained
host WAD. Hardware result collection must additionally audit the complete
disposable disk for unrelated changes.

These are real-mode DOS file reads. Passing does **not** prove Doom's protected
runtime payload, memory tables, interrupt state or renderer correctness.
CRC32 detects errors but is not cryptographic identity. Whole-second timing
has endpoint quantization; zero is below resolution. Ordered passes may have
different cache state, and the checksum loop's cost must not be mistaken for
Doom's loading cost. This is not a Doom startup benchmark.
