# SDRAM control synchronization

The b700d62 60 MHz fit fails CPU-completion setup by 0.300 ns and request
reception by 0.262 ns. CPU/SUB completion previously fed ACK and returned-data
capture directly across adjacent 60/100 MHz PLL edges. Request reception had
three flops but also used the raw request to clear a receipt signal.

CPU and drawing requests now toggle once per accepted transaction. Memory
admission compares stages two and three of the request pipeline, so its
first stage feeds only stage two. The operation and write/address payload
are captured together on the existing third memory edge. Operation type
stays held until the next transaction; the receipt/clear feedback is removed.

Completion passes through two CPU/SUB flops before the existing change
detector registers ACK and read data together. This adds **two source-clock
waits** to an uncached completion; it does not change SDRAM command counts,
burst lengths, byte masks or memory-domain read/modify/write arithmetic.
CPU ACK remains a one-cycle pulse. Drawing ACK remains asserted until its
strobe is released. Source request/return data remain held through the
round trip. The common reset clears both toggle histories.

`pc98-sdram-control.sdc` excludes only the eight first-stage request/return
registers of CPU/SUB/FDE/FEC. All inter-stage paths and consumers remain timed.
The operation-type route receives the same 15 ns setup bound as the payload:
admission at 100 MHz occurs at least 20 ns after source acceptance, leaving
at least 5 ns to settle. Ordinary operation hold checks remain enabled.
Missing synchronizer or operation endpoints abort timing analysis.

`tests/run-sdram-control-cdc.sh` injects 15 ns operation routing and checks
5 ns setup at every admission, across all four clients at six source rates
and four memory phases. CPU/drawing checks include held completed strobes;
floppy checks include continuously asserted requests. CPU/drawing read
capture also requires the completion toggle stable for 20 ns (two periods
at the fastest tested 100 MHz rate). Late 80 ns operation data and bypassing
either completion synchronizer must fail. Existing data-route, read/write/
RMW, completion, floppy and video regressions remain necessary.

Simulation checks protocol behavior, not analogue metastability. A new fit
must verify every surviving endpoint, all timing corners and real hardware
performance. The extra waits may offset a clock-rate gain; compare against
the FullFont50 benchmark (247 ALU / 130 RAM-copy / 102 stack blocks per
1,000 DOS hundredths, all checksums passing) before choosing a default.

The regression passes: 18,432 CPU/drawing commands and 12,288 continuous
floppy requests with delayed operation metadata, all four late-operation
controls, and both completion-bypass controls. CPU/drawing write/return
payload sweeps, held-completion checks, legacy requests, floppy transfers,
and the real graphics scanout pipeline also pass, including their negative
controls. The one-CPU/2-GiB container exited zero without OOM and was removed.
Log: `build/sdram-control-cdc-regression-v2.log`. The first attempt stopped
in the test injector because it matched a commented-out legacy assignment;
no RTL result was inferred from that failed preparation.
