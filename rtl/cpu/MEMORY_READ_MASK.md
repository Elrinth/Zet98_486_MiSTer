# ao486 read-mask contract

The PC-98 CPU wrapper enables `READ_MASK_ALWAYS_NONZERO` in its memory bridge.
This is specific to the connected vendored `memory/avalon_mem.v`, not a general
Avalon guarantee. The reusable bridge defaults the option off and retains its
full-read fallback for a zero byte-enable mask.

In this ao486 implementation, `avm_read` can only be asserted in the idle state
with reset released and no `writeburst_do`. CPU data and code requests then
select `len_be[readburst_address[1:0] +: 4]`. Every possible four-bit slice is
nonzero for every length encoding, including the default case. DMA selects a
one-byte or two-byte mask, also nonzero. The saved mask for later write beats
is not selected while `avm_read` is asserted. Conflicting request flags do not
invalidate this implication because the read assertion and mask mux have
compatible priority.

This lets the first-half decision use only the two lower mask bits, read/write
kind and burst count. It no longer needs the length-dependent upper bits to
detect a zero mask. The acceptance edge, transfer states and acknowledgement
release behavior are unchanged. Writes still accept all sixteen masks.
Multi-beat reads still fetch complete words regardless of the initial mask.

`tests/run-memory-mask-contract.sh` instantiates the actual vendor module and
exhausts all inputs in this property's combinational support: all eight state
encodings, both reset values, all five request flags, sixteen read lengths,
four read offsets, four DMA offsets and both DMA widths. That is 262,144 cases
with 7,168 asserted reads. A mutation which emits an empty read mask must fail.
An assertion in the optimized bridge also rejects a violated read contract.

The same runner checks the reusable bridge's zero-mask fallback, every byte
mask, bursts, held acknowledgements and reset, then connects the actual Avalon
generator to the optimized bridge. Full CPU, REP instructions, extended RAM,
self-modifying code, DMA and upper-memory cache tests exercise the integration.

The preceding 60 MHz ControlSync fit failed by 0.034 ns on a CPU read-length
path ending at `memory_bridge|high_half`. This change targets that dependency;
it does not establish a frequency increase until a fresh fit passes every
timing corner and the hardware diagnostics pass. It introduces no new timing
exception.

The cdf93b9 MaskGrcg60 fit no longer reports this bridge dependency among its
worst paths. It still fails timing elsewhere: video-measurement sampling at
-0.088 ns and a CPU breakpoint-address feedback path at -0.070 ns. The latter
is addressed in `DEBUG_ADDRESS.md`; this fit remains undeployed.
