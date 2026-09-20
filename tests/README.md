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

The full CPU test is `tests/run-cpu.sh`. It assembles `ao486_smoke.asm` with NASM
and runs the unmodified ao486 CPU/cache sources with the PC-98 CPU wrapper and
Intel RAM models. It checks a 486-only instruction (`BSWAP`), unaligned DWORD
memory and odd-port I/O, `REP MOVSD`, A20 wrapping and unmapped-memory isolation,
high reset-ROM aliases, interrupt/IRET, and a CPU-only reset that retains RAM.
The upstream simulation observer is supplied as a read-only test hook.

Icarus 11 propagates pull defaults from some Intel model input ports into
connected Verilog registers. The test script inserts identity expressions at
those connections in temporary simulation copies. Vendored and synthesized
sources remain unchanged. These tests use actual CPU execution but not the
complete PC-98 peripherals, real BIOS or floppy images.
