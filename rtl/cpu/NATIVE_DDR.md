# Native DDR memory path

This opt-in path preserves DWORD requests from the CPU through to DDR instead
of splitting them into two halfword handshakes. Enable it with
`scripts/build.ps1 -NativeDdr` in an ao486/z486 build with extended RAM.
The default remains the B240 memory path.

The memory bridge selects the native backend only for an entire burst inside
extended RAM or an enabled linear PEGC framebuffer alias. Low RAM, ROM, MMIO,
banked graphics, unmapped addresses and bursts crossing an aperture boundary
continue through the legacy decoder. The 15–16 MB aperture remains excluded
from ordinary RAM. `00F00000h` and `FFF00000h` framebuffer aliases both reach
the existing `30F00000h` DDR backing.

A store becomes one 64-bit DDR command with four byte enables shifted into the
correct DWORD half. A read uses both DWORD halves of each fetched 64-bit word
when the requested burst includes them. CPU responses remain individual
DWORDs; no game, BIOS or instruction-set changes are required.

Stores still complete at DDR acceptance. The shared bus retains ownership
until the transfer finishes, so later I/O stays ordered. Accepted DDR reads
retain their response tag through CPU-only or global reset; canceled data
drains without completing a new request. The fallback extended-RAM read
buffer is disabled in native builds because stores can bypass that buffer.

## Validation

`tests/run-native-ddr.sh` checks all store byte masks, both DWORD halves,
bursts of 1–8 words, high/low graphics aliases, DDR stalls, zero-latency
responses, canceled writes, reset draining and RAM/graphics boundary
coherence through the actual router. `tests/run-z486-native-ddr.sh` runs
real z486 instructions with the B240 pipeline configuration, comparing the
old and new paths and testing a reboot during a pending DDR read.

The self-authored workload initializes a 64,000-byte source, copies it into
the framebuffer with `REP MOVSD`, then verifies every DWORD through the
high framebuffer alias. With the same modeled DDR waits and CPU instructions:

- Frame copy: 504,083 → 268,884 CPU clocks, 46.66% fewer clocks.
- Complete initialization/copy/readback workload: 1,479,353 → 1,013,753
  clocks, with 128,045 issued instructions in both runs.
- DDR commands for that complete workload: 104,000 → 56,000.

These are simulation measurements of memory transfers. They do not establish
Doom FPS or hardware timing. Hardware qualification results belong below.
