# CPU and peripheral simulation

The I/O adapter targets the native byte-address/length interface of MiSTer
ao486 commit `9d888c485bcf2e781824b303588668529a02015e`. The adapters are connected
to the optional ao486 build; simulation does not establish faster game performance.

It retains PC-98's low/even and high/odd byte lanes, preserves aligned 16-bit
register accesses, and splits unaligned and 32-bit transfers. The peripheral
fabric now decodes both selected lanes independently in the Zet98 top level.
CPU and peripheral clocks are the same in this unit test; a clock-domain
bridge is still required for independent CPU and peripheral rates.

The memory adapter converts DWORD-addressed reads of up to eight beats and
single writes into acknowledged 16-bit transfers. It preserves all 32 physical
address bits; BIOS aliases and PC-98 memory mapping are deliberately left to
the system integration. Reads return full DWORDs because ao486 instruction
fetches can carry byte enables left over from unrelated data reads. Write
burst counts can likewise reflect a pending read; each write is still a single
DWORD command, split according to its actual byte enables.

`ao486_bus_bridge` arbitrates the two adapters onto one memory/I/O bus. It drains
pending memory commands before granting I/O, including the second command of
an unaligned ao486 write. A granted I/O transaction retains ownership through
every halfword and the final acknowledgement release.

From the repository root in PowerShell, `./scripts/test.ps1` runs all tests.
It builds the simulation image, then obtains Intel RAM models from the locally
installed Quartus image into ignored `build/intel-sim/`. No BIOS/game files are
used. `-AdaptersOnly` skips the full CPU test and its Intel-model dependency.
To run only the bus/peripheral tests manually:

```powershell
docker --context desktop-linux build -t zet98-sim -f tests/Dockerfile .
docker --context desktop-linux run --rm --network none --mount "type=bind,source=$($PWD.Path),target=/project,readonly" zet98-sim bash tests/run.sh
```

The bench checks byte, word and dword transfers at even/odd addresses,
16-bit port-address wrapping, correct peripheral byte-lane side effects,
wait-state stability, acknowledgement release and reset during a request.
The memory bench checks all 16 write masks, bursts of one through eight DWORDs,
addresses above 1 MB and at the 32-bit wrap boundary, queued requests, stalled
transfers, acknowledgement release and reset during a burst.
An additional integration bench uses the unmodified upstream `avalon_mem`
request generator. It verifies unaligned data reads/writes, complete eight-beat
instruction fetches with unrelated byte enables, byte/word DMA transfers through
the ao486 DMA input, and concurrent I/O with pending memory traffic. This does
not yet connect Zet98's existing external DMA controller or the full ao486 CPU.
The combined adapter also passed standalone Quartus 17 Analysis & Synthesis
for `5CSEBA6U23I7` on 2026-09-20 (347 logic cells before fitting). This is a
synthesis compatibility check, not timing closure or a complete core build.
The VHDL bench also compares OPNA/PIT enable rates and the VFO interrupt pulse
width at 20 and 40 MHz. These tests do not verify complete machine integration, BIOS boot,
complete peripheral timing, or Rusty performance.

Video regressions check the replacement text row counter against the original
absolute-line modulo formula over 33,600 scanlines (all 32 character heights,
two full frames each). The registered video-output test checks native RGB/sync
alignment and hold behavior, plus the diagnostic raster's 800x525 total size,
640x480 active area, sync pulse widths, blanking and divide-by-three pixel
enable. These are logic tests; they do not establish hardware video stability.
An integration test with the original `VTIMING` generator also checks row
alignment for 1,247,400 pixels across 16-, 20- and 32-scanline text modes,
after its initial partial scanline on reset.

The startup-speaker mute test verifies exact expiry, automatic restoration,
timer saturation, reset rearming and the menu bypass. Changing the bypass
after the startup interval must not mute later speaker audio. Clock and duration
generics are reduced for simulation; the core uses its system clock frequency
and a 10,000 ms interval.

`run-disk-interface.sh` drives real HPS commands through the core's actual
SystemVerilog wrapper and `hps_io`. It transfers 512-byte reads and writes on
each of four image slots and checks per-slot/shared ACK lifetime, LBA, the
single-block request size, buffer payload/address and mount metadata. The
machine and Intel clock primitives are stubs; the bench does not exercise the
VHDL floppy controller or real disks. Unrelated PS/2 and configuration-ROM
logic is disabled in the bench. A temporary `hps_io` copy supplies parameter
defaults required by Icarus; both values are overridden by the actual instances.
This catches the previous scalar ACK connection, which discarded slots 1–3.

`run-data-bus.sh` compiles the marked data-bus expressions directly from the
machine top level. Its reference is the historical mux before DMA feedback
removal, preserved under `reference/`. It compares 77,748 cases: every pair
of device enables, all byte-lane masks, CPU/DMA ownership, interrupt-acknowledge
gating, sparse random selections, and both DMA byte-routing directions.
Directed FDC-to-memory and memory-to-FDC cases check even/odd byte placement.
It also compares each selected CPU I/O write byte (including loader precedence)
against the historical shared bus. This verifies the direct write path while
unrelated peripheral read enables and DMA ownership vary. An additional 20,000
DMA memory-to-FDC and FDC-to-memory comparisons cover both byte addresses and
memory-device priority. The actual GRCG is also instantiated: 4,096 plane
results check CPU/DMA write masks against delayed memory read data, and tile
comparison checks distinguish matches in the high and low bytes on every plane.
This verifies mux behavior; it does not simulate the complete DMA controller.

`hardware/disk_probe.asm` is a small DOS shell for real-hardware disk diagnosis.
It is assembled with NASM `-f bin` and inserted into a new copy of a user-supplied
system D88 using `scripts/d88_file.py`; see `HARDWARE_TESTING.md`. No BIOS, DOS
or game data is included in the tests. A DOS-reported successful log write is
not proof that the core has persisted it to the host D88.

The full CPU test is `tests/run-cpu.sh`. It assembles `ao486_smoke.asm` with NASM
and runs the imported ao486 CPU/cache sources, including the documented local
cache changes, with the PC-98 CPU wrapper and
Intel RAM models. It checks a 486-only instruction (`BSWAP`), unaligned DWORD
memory and odd-port I/O, `REP MOVSD`, A20 wrapping and unmapped-memory isolation,
high reset-ROM aliases, interrupt/IRET, and a CPU-only reset that retains RAM.
The upstream simulation observer is supplied as a read-only test hook.

Icarus 11 propagates pull defaults from some Intel model input ports into
connected Verilog registers. The test script inserts identity expressions at
those connections in temporary simulation copies. Vendored and synthesized
sources are not altered by the simulation workaround. These tests use actual CPU execution but not the
complete PC-98 peripherals, real BIOS or floppy images.

`run-cache.sh` uses the real instruction cache and Intel RAM models to test
warm hits, level-held/repeated invalidation, a request queued during tag clearing,
and invalidation during an outstanding burst. A full CPU program then runs with
cache off and on: it checks externally modified warmed code, CPU self-modifying
code, uncacheable upper-window code, and ALU/VRAM-copy checksums. The synthetic
bus uses eight added wait cycles by default (`+wait=N` overrides it). It prints
cycles and bus transfers for two small hot loops; these are diagnostic
microbenchmarks, not Rusty frame rates or a model of complete SDRAM arbitration.
A negative control disconnects invalidation and must fail on stale code.

`run-cache-map.sh` combines the actual memory mapper with the marked production
invalidation expression. It checks 3,328 bank/read/write/I/O cases plus DMA
ownership. The DMA grant test separately checks requesting an already idle bus,
waiting for an active CPU transfer, retaining ownership and release/reset.

`hardware/cpu_bench.asm` assembles with NASM's `cpu 8086` restriction and runs
on a disposable System-disk copy. It synchronizes to a DOS-clock transition,
executes ALU and RAM-copy blocks until at least ten reported seconds elapse,
checks their results, and writes `Z98PERF.TXT`. Each block has 131,072 iterations.
Compare blocks per reported second using the same BIOS/settings. The clock may
have coarse resolution despite expressing its result in hundredths; this is
a synthetic throughput test, not a game frame-rate test.
