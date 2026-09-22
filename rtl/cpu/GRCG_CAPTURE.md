# GRCG memory diagnostic

`tests/hardware/grcg_memory_probe.asm` checks the graphics writes that follow
font expansion. It contains synthetic patterns, without game or ROM bytes.
Assemble with `nasm -f bin -DPROBE_SHELL=1` and install it as the shell of a
disposable DOS floppy without memory managers. The program requires CS at or
below 6000h and an allocation through 91000h before touching upper RAM. Use
native conventional-memory banking; the capture records ports 0461h/0463h,
but the allocation guard cannot prove their mapping.

The probe changes both graphics pages and enables sixteen-color plane access.
It restores the CPU page and disables GRCG before saving. Each page starts
with distinct bytes in all four planes. It then exercises aligned and odd
word RMW copies, byte RMW copies, sparse odd-byte writes, TDW with two planes
disabled, and pairs of two-word rows duplicated at an 80-byte pitch. Source
data comes from both the program segment and segment 9000h. Re-reading both
pages after the writes also checks page isolation. Interrupts are disabled
during the graphics operations; concurrent interrupt-driven drawing and EGC
are outside this probe's coverage.

`Z98GRCG.BIN` is created exclusively. Its 32,912 bytes contain a 16-byte header
and 32 records, each with four metadata bytes and four 256-byte plane blocks.
The capture buffer is separate from the COM image and guarded against code
and stack overlap. Unload the core and verify that the disposable disk is
closed before retrieving the result.

```sh
python scripts/d88_file.py result.d88 Z98GRCG.BIN Z98GRCG.BIN
python scripts/verify_grcg_memory_probe.py Z98GRCG.BIN
```

The verifier uses individual pixel selection for RMW, independently of the
HDL's byte expression, and requires exact record ordering and length. Tests
against the reference capture detected one changed byte in each of the 128
plane records and rejected eight malformed header/length cases.

On 2026-09-22, NP2kai revision
`5939e0c6d5985c4c08fc70f289a83290e5d3e6f7` and SuperStation One UpperCache50
(source `0939a06`) each pass all 32,768 pixel bytes with zero mismatches.
Both report CS=120Eh and allocation end A000h; the FPGA reports banks 08h/0Ah
while the reference returns FFh/FFh for those ports. Their capture hashes
therefore differ despite identical pixel data:

- Reference: `12f6977724b705ddf5119cad0207620f420b359efc432cd0f53c1fc8f938bbcc`.
- FPGA: `e91ab63eda1822ed6c24a5296f5e109c56ba40bc40af0d9926184ac0a7bdd05f`.
- Retrieved FPGA D88: `3acc0dc56576f060b2f6f6efe933060078656661f1f1c93d129083589a557a24`.

These results rule out errors in the tested write sequences and page layout.
They do not prove the complete Rusty renderer correct: its title-menu glyphs
remain malformed on UpperCache50, requiring observation of the game's actual
data and execution or a failing combined reproducer.
