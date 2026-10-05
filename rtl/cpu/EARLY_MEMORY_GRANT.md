# Accept memory commands while granting the idle bus

The shared memory/I/O bridge previously granted ownership on one clock edge,
then accepted the CPU memory command on the next. The early-grant path lets
the memory bridge latch the command on the ownership-granting edge. Actual
legacy or native transfers still start from the bridge's registered state.

An active I/O owner, a lingering legacy ACK, reset, or an outstanding native
DDR response still blocks admission. Memory retains its existing priority
when both memory and I/O request an idle bus. This changes no memory mapping,
cache policy, CPU instruction, peripheral timing, or write-completion rule.
Set `EARLY_MEMORY_GRANT=0` on `pc98_ao486` or `ao486_bus_bridge` to compare
against the previous behavior.

`tests/run-early-memory-grant.sh` checks the real ao486 Avalon generator with
both direct and eight-entry queued memory commands, concurrent I/O, split
unaligned stores, code fetches and DMA. It also checks native/fallback DDR
response ownership through CPU resets. An intentionally broken ownership
guard is rejected by the concurrent-I/O test.

`tests/run-z486-memory-completion.sh grant` compares actual z486 execution
with the optimization disabled/enabled. It retains the store-completion and
resident-read improvements in both modes. With PR2, 32 KB instruction cache,
8 KB data cache and native framebuffer only, initial simulation results are:

- RAM-to-linear-framebuffer copy: 308,087 to 285,685 clocks (7.27% fewer).
- Full fill/copy/readback workload: 1,053,345 to 1,019,724 clocks (3.19% fewer).
- Both execute 128,045 instructions and issue 72,000 DDR commands.

These are simulation measurements. FPGA fit, timing and hardware qualification
must complete before claiming a Doom improvement or promoting this candidate.
