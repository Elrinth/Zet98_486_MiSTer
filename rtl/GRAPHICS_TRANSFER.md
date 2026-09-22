# Completed graphics data crossing

SDRAMC publishes four VIDDAT words, then toggles `vidend`. Two pixel-clock
synchronizer stages precede VIDACK. GRAPHSCR98 captures the completed words
into WDAT only in BS_READ with GRAMACK high. The line RAM receives WDAT on
the following pixel edge. The 64-bit crossing is a held data bundle; its
completion control is synchronized separately.

The capture edge also lowers GRAMRD. On the next pixel edge SDRAMC clears
`lVIDstb`, while GRAPHSCR advances its address and raises GRAMRD for the next
word. Only on the second pixel edge after capture can SDRAMC toggle a fresh
VIDREQ. That request must cross the memory-clock synchronizer and complete
a new read before VIDDAT can change. The source therefore holds its old data
for more than two 40 ns pixel periods after the enabled capture. An adjacent
arbitrary 100 MHz edge cannot change that captured value.

`pc98-graphics-transfer.sdc` retains the existing 20 ns setup bound from
VIDDAT to WDAT, but excludes the hold check between arbitrary clock edges
for those exact register groups. The former ordinary hold constraint could
require a routing delay solely to compensate for generated-clock insertion
skew, although the transfer is not enabled on the edge in question. There
is no new setup exception or global clock-domain exception. Address hold,
the same-clock WDAT-to-line-RAM transfer, configuration, control synchronizers,
ACK and BUFWE remain timed as before.

This distinction appeared in FullFont50 (source e5aa389): all five negative
summary checks were hold checks, worst -3.434 ns. The detailed worst path
was SDRAMC VIDDAT to GRAPHSCR WDAT with about 7.4 ns clock skew and 4.2 ns data
delay. The build was withheld while the actual enabled capture was checked.

`tests/run-video-sdram.sh` instantiates the production SDRAMC and GRAPHSCR98
with a modeled SDRAM responder and line RAM. It verifies plane contents,
addresses, order, count, live page changes, and CPU contention. Each enabled
WDAT capture must have at least 20 ns stable input before it and both the
producer and routed inputs must remain stable for 20 ns afterward. There
must be exactly 640 post-capture checks per run. The next line-RAM write
also checks its 20 ns setup margin.

On 2026-09-22, all 108 combinations pass: CPU rates 20/40/50/60/90/100 MHz,
six memory/pixel phase offsets, and data routes of 0/20/40 ns. This includes
69,120 enabled capture hold checks. A deliberately late 200 ns data route,
a 1-to-5 ns post-capture glitch, and an unsynchronized display-page bypass
are each rejected by their corresponding check. The glitch is essential:
data-order and setup checks alone cannot validate post-capture stability.

These simulations establish the tested handshake contract, not analogue
metastability behavior or complete board timing. Fitted timing must still
check the retained setup bound, synchronizer stages and all other clocks
at every available operating corner before a bitstream is used.

Re-analysis of the unchanged FullFont50 fitted database with this one SDC
change passes setup, hold, recovery and removal at all four available
operating corners (minimum +0.082 ns). The original pulse-width checks remain
positive and are unaffected by this data-hold exception. The SPI, HDMI I2C
and UART fitted-pin guards also passed. The local audit is
`build/fullfont50-hold-audit.json`; the unchanged RBF SHA-256 is
`41009f06741fbe4a28746725b85eb66b2fb889c3619693b76057a28ae9537f97`.
Keep that revised audit with the bitstream: the original build's summary
correctly records failure under the superseded hold constraint.
