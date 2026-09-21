# ao486 source provenance

This directory's Verilog, QIP and command-generator source files originate
from [MiSTer-devel/ao486_MiSTer](https://github.com/MiSTer-devel/ao486_MiSTer)
commit `9d888c485bcf2e781824b303588668529a02015e`, under `rtl/ao486/`.
The matching `rtl/cache/l1_icache.v`, `rtl/common/simple_fifo_mlab.v` and
`rtl/common/simple_mult.v` are stored in the sibling `cache/` and `common/`
directories. Their original notices are retained. The upstream root license
is copied as [ao486-LICENSE](../ao486-LICENSE), including its BSD terms for `rtl`.

The full CPU is instantiated by `rtl/cpu/pc98_ao486.sv` in the opt-in ao486 build.
The default remains Zet. This import does not include ao486's IBM PC platform,
DDR3/L2 cache, VGA, BIOS, sound card or disk controller. PC-98 adapters live
separately under `rtl/cpu/`.

Local changes to `ao486.v` and `memory/memory.v` carry a cache-invalidation
input to `memory/icache.v`. The latter bypasses instruction caching outside
fixed low RAM (below 80000h) and resets prefetch during external invalidation.
The sibling `cache/l1_icache.v` drains outstanding fills and clears all tags
before resuming after invalidation. This supports the PC-98 external DMA fabric
without pretending its writes pass through ao486's built-in DMA/snoop port.
Original license notices are retained; other imported sources are unchanged.
