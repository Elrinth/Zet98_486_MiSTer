# Conventional RAM diagnostics

Rusty's font expansion routine in the private reference run executes at
CS=8BDEh, reads font bytes into physical 907E4h and looks up words in a table
starting at odd address 91593h. Correct character-ROM reads alone do not
verify these subsequent memory accesses or the graphics writes.

`tests/hardware/conventional_bytes_probe.asm` tests 70000h, 80000h and 90000h.
It writes an independently generated pattern with byte stores, then captures
byte reads, aligned words, odd words crossing word/cache-line boundaries,
and partial-byte updates. It refuses to run unless the DOS COM allocation
owns every test location and the program/stack lie below the test area.
Use it as the shell of a disposable DOS floppy without memory managers;
assemble with `nasm -DPROBE_SHELL=1 -f bin` and set SHELL to that COM file.

The probe creates a new `Z98BYTE.BIN`, never replacing an existing result.
After unloading the disk and extracting the file, verify it with:

```
python scripts/verify_conventional_bytes_probe.py Z98BYTE.BIN
```

The reference emulator and FontMap50 hardware both pass all twelve checks
(9,240 captured data bytes, zero mismatches). The hardware bank registers
read 08h/0Ah, their native mapping. The 9,262-byte hardware capture has SHA-256
`5bdf1da1c340f0e18e1fcc344b852ad60d769a606563e6fd0c7133fc692bae5e`.
The verifier rejects corruptions in each read/write class and malformed
capture lengths/headers. This rules out the tested basic access failures;
it is not an exhaustive RAM test or proof of correct Rusty rendering.

The current instruction cache excludes addresses at or above 80000h. The
reference font routine therefore identifies a concrete uncached workload.
Caching this region requires native bank-89 mapping, invalidation on mapping
changes, and coherence for DMA and writes through the bank-AB alias. Merely
widening the address comparison is insufficient.
