# Glyph expansion diagnostic

`tests/hardware/glyph_expand_probe.asm` isolates the CPU operations used to
expand and shift monochrome glyph pixels. It contains synthetic patterns and
no game or ROM bytes. It complements the font-port and conventional-RAM
probes: correct font bytes alone do not prove that the rendering arithmetic
and its odd-address lookup table work.

Assemble with NASM as a flat 8086 COM program. `-DPROBE_SHELL=1` leaves the
result on screen; the default returns to DOS. Use only a disposable DOS boot
disk without memory managers and with native conventional-RAM banking. The
program requires CS <= 6000h and a PSP allocation through at least 93000h
before touching the test regions. These guards verify DOS ownership, not the
bank mapping. The capture records ports 0461h/0463h for inspection.

The probe copies the same position-independent kernel to segments 7000h and
9000h. Each invocation expands all 256 source byte values and XOR-A5h partners
through a word lookup table at the deliberately odd offset 1593h. It then
shifts each 32-bit pixel group through AH, AL, DH and DL using SHL/RCL. It
captures both 1,024-byte output stages per segment, so the run exercises both
low and upper instruction fetches, odd word reads, byte-register carry
propagation and stores.

`Z98GLYF.BIN` is created exclusively and never replaces an earlier capture.
Its 4,116 bytes contain a 16-byte header and two records with a segment number
and 2,048 output bytes. Unload the core and confirm the disposable disk is
closed before retrieving it. Verify the extracted result with:

```sh
python scripts/verify_glyph_expand_probe.py Z98GLYF.BIN
python tests/test_glyph_expand_probe.py
```

The verifier uses concatenated pixel strings and a whole-word arithmetic
shift as its independent oracle. Its tests construct the expected capture
with bit-position arithmetic; corruptions in all four regions, wrong byte
order, malformed headers, unsafe ownership and incorrect record ordering
must be detected. A passing capture checks 4,096 pixel bytes. It does not
verify the subsequent GRCG writes, VRAM layout or complete game renderer.

On 2026-09-22, SuperStation One with UpperCache50 (source 0939a06) passes all
four checks: 4,096 bytes, zero mismatches. The capture reports CS=120Eh,
allocation end A000h, bank 89=08h and bank AB=0Ah. The result was retrieved
after unloading the core and checking that the diagnostic disk was closed.
Capture SHA-256:
`9d56430ba6d96ba3e839aea44a7be9fbb197d246f2e7fed350e9ddc58d173311`.
Returned D88 SHA-256:
`086038a35dd4fb8e15d6efa52f229a2ca2a1ded061833381e287994517f0fc6d`.

Rusty's title menu is still malformed on this build, while its logo, dialogue
and first gameplay scene render. The isolated arithmetic result directs the
next investigation toward graphics writes and integration with font access;
it does not rule out every CPU operation or interaction in the game.
