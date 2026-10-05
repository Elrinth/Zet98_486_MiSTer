# Park the idle bus at its memory owner

The shared memory/I/O bridge previously released an idle memory owner and
waited for a new CPU command before granting memory ownership again. Keeping
an idle bus assigned to memory removes that extra grant cycle. Ownership
remains registered, and ready does not depend on the arriving CPU request.
Actual legacy or native transfers still require an accepted command.

An active I/O owner blocks memory admission. The bridge drains its memory
commands and legacy ACK before handing ownership to I/O. After reset, an
outstanding native response must drain before ownership can be assigned.
Memory retains priority when both memory and I/O request an idle bus. An
empty parked grant does not count as pending work; queued commands, ACK
release and native response draining still do. This changes no memory mapping,
cache policy, CPU instruction or write-completion rule.
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
8 KB data cache and native framebuffer only, all 84 comparison cases pass.
Simulation results are:

- RAM-to-linear-framebuffer copy: 308,087 to 285,685 clocks (7.27% fewer).
- Full fill/copy/readback workload: 1,053,345 to 1,019,724 clocks (3.19% fewer).
- Both execute 128,045 instructions and issue 72,000 DDR commands.

These are simulation measurements. FPGA fit, timing and hardware qualification
must complete before claiming a Doom improvement or promoting this candidate.

## Rejected combinational grant experiment

Commit `44b0d44` accepted commands on the idle ownership-granting edge using a
combinational request-qualified ready signal. It passed the integration tests,
84 CPU cases and 40 differential seeds, and fitted in 4,189 of 4,191 LABs with
worst setup slack of -7.746 ns. Nevertheless, two fresh hardware Linux boots
panicked at different kernel addresses (`c02ca0df`, then `c01a9c16`). The
qualified original core booted the same image and passed three stack probes
and 100 traced `ip` launches immediately afterward. The combinational version
is not qualified.

The parked-owner implementation removes that new combinational request-to-ready
path. Whether this resolves the hardware failure remains to be tested; the
failure's root cause has not been established.
