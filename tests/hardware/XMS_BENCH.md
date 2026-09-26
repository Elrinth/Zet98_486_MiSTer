# XMS allocation and copy timing probe

`xms_bench.asm` is self-authored and contains no game or memory-manager code.
It uses the installed PC-98 XMS driver through the standard INT 2Fh entry.
Run it only from a fresh disposable DOS fixture with the same Z98MEM/HIMEMX
configuration being investigated. Do not replace an existing completed probe.

Status: assembled and all 13 independent protocol/error-model cases passed.
Hardware timing measurements remain pending. Model timings are not hardware
performance results.

The probe compares:

- One allocation of 1,043 KB.
- One allocation of 8,192 KB, matching Doom's observed zone size.
- Growth from 19 KB to 1,043 KB, using 64 separate 16 KB resizes. This ends at
  the same size as the first allocation and checks preservation of 16 KB of data.
- Eight 1 MB copies between separate XMS blocks. Source initialization and
  verification are outside the timed interval. Every byte of the final 1 MB
  destination is checked, with a different pattern in each 16 KB chunk.

Every XMS call enters with interrupts disabled, matching the existing resize
reproducer. The wrapper restores the caller's flags afterward. Timing uses the
PC-98 BIOS hardware-calendar read (INT 1Ch, AH=00, ES:BX six-byte result) rather
than DOS or PIT interrupt ticks, which can lose time while IF is clear. The
hour/minute/second bytes are BCD checked and the clock must advance before any
measurement. Midnight rollover is handled. Confirm the BIOS calendar advances
at wall-clock rate on the real machine before interpreting results.

Results have **whole-second resolution**, with approximately one second of
endpoint uncertainty. A zero result means the operation was shorter than this
measurement resolution. The timed resize/copy loops include sparse progress
output and timer-read overhead; results are not pure bus-bandwidth figures.
The copy report states bytes submitted, not an assumption about physical DDR
transactions. Do not infer that every resize copies the whole old allocation
without separate evidence from the actual driver.

Each phase has a 120-second budget checked between calls, and all request loops
have fixed maximum counts. An XMS call that never returns cannot be safely
preempted here; supervise the run from the host with a bounded overall deadline.
The probe frees its handles on success and attempts cleanup on errors. A new
`XMSBENCH.TXT` is created with DOS create-new semantics: an existing result is
never overwritten. The program also reports progress and errors to the screen.

Assemble and validate **only when no FPGA/simulation job is running**:

```powershell
build/tools/nasm-2.16.03/nasm.exe -f bin tests/hardware/xms_bench.asm -o build/hardware/xms-benchmark-r1/XMSBENCH.COM
python tests/xms_bench_unicorn.py build/hardware/xms-benchmark-r1/XMSBENCH.COM
```

The Unicorn test runs the actual assembled program against independent RTC,
DOS, and XMS models. It checks operation counts/sizes, IF state, full data
validation, error cleanup, midnight wrap, stopped/invalid clocks, allocation
and resize failures, data corruption, time-budget exit, and no-overwrite/error
file handling. It is not an emulation of the real HIMEMX driver or a performance
measurement. Hardware results must record the core hash, driver/config hashes,
fixture provenance, start/end wall times, console captures, and collected file.
