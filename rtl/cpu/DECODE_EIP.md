# Instruction-length carry selection

The FullFont60 fit at source 4790ba7 has a slow/hot system-clock path of
+0.253 ns from operand-size decoding through instruction-length calculation
and the instruction-pointer update. Length arrives late enough that adding
it through a full 32-bit carry chain limits further CPU clock increases.

`rtl/vendor/ao486/pipeline/decode.v` now splits the addition at bit four.
Instruction length is four bits: it can change the upper 28 bits only by
carrying one out of the low nibble. The upper increment is computed in
parallel and selected by that carry. A Quartus `keep` attribute preserves
the independent increment net. There is no new register, instruction cycle,
stall condition or architectural state.

`python3 tests/prove-decode-eip.py` extracts the production EIP combinational
and sequential block and compares it with ordinary 32-bit addition and the
original reset/redirect/ready contract. Yosys proves all lengths 0..15 and
arbitrary EIP values, including wraparound and changing control inputs.
Wrong carry selection, an omitted upper increment and lost redirect priority
each produce a counterexample. The proof passes; its first container attempt
lacked an include file, which was supplied before the successful run.

The full-CPU regression also passes: uncached smoke, cached REP count cases,
16/64 MiB protected-mode access and real-mode return, lower-cache coherence,
and upper instruction caching with native/aliased stores, DMA and bank remaps.
The oversized-memory and disconnected-invalidation controls fail as intended.
The cached ALU/VRAM/stack measurements remain 6,392/3,720/5,268 cycles;
the upper-RAM loop remains 218,562/5,470 cycles with caching off/on. Thus the
tested workloads acquire no added cycles. The test container exited zero
without an out-of-memory event and was removed after its log was saved.

The change still requires a new FPGA fit and timing comparison. In particular,
FullFont60's separate video-setting and HDMI scaler violations remain open;
this optimization alone does not establish a working 60 MHz core or a game
frame-rate increase.

HostSettings60 at b700d62 is the first fitted snapshot including this change.
Its slow/hot CPU-only minimum is +0.087 ns; the cold decoder-buffer count path
still fails by 0.151 ns. Other memory/HDMI failures also remain, so the fit
is not deployed. Physical placement changed and this result does not prove
a standalone frequency improvement. The next buffer optimization is described
in `DECODE_BUFFER.md`.
