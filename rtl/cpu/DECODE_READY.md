# Instruction-buffer ready path

The previous 60 MHz CPU path started in execution/read backpressure, crossed
micro_busy, then entered consume-count arithmetic and the 96-bit decoder
buffer mux. Its measured data delay was 15.799 ns. Higher clocks need a
shorter combinational path; adding a CPU clock setting alone cannot fix it.

The buffer now computes both consume and stall results before the late
ready decision, then selects the completed data/count/acceptance tuple.
Instruction lengths, prefix handling, reset priority and all stored bits
retain their original behavior. No pipeline stage or cycle is introduced.
Prefix consumption still has its original priority over reset/micro_busy.
The pure function retains the original arithmetic widths and mux defaults,
including encodings outside the ordinary reachable buffer-count range.

The reference test compares 131072 count/consume/prefix/fetch/stall cases
and 10000 sequential cycles, including resets and underflow encodings.
Forcing consumption during a stall must fail. The full CPU smoke test,
both cached coherency configurations, disconnected-DMA negative control,
and actual CPU BIOS-write test pass. Cache benchmarks retain exactly
6361/4543 cycles (instruction cache) and 6393/3720 cycles (instruction plus
8 KB conventional-memory cache). The uncached stress run reached its
434005-cycle ALU result before diagnostic interruption; its full rerun is
pending. No timing or hardware speed claim follows from these simulations.

An isolated 66 MHz CPU/bridge fit is running. Its virtual I/O constraints
cannot establish complete PC-98 core timing, hardware reliability or game
frame rate, even if the CPU-only result passes.
