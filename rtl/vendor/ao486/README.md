# ao486 source provenance

The files `memory/avalon_mem.v`, `defines.v`, `startup_default.v` and
`autogen/defines.v` are copied without modification
from [MiSTer-devel/ao486_MiSTer](https://github.com/MiSTer-devel/ao486_MiSTer)
commit `9d888c485bcf2e781824b303588668529a02015e`, under `rtl/ao486/`.
Their original copyright and BSD license notices are retained in the files.

This initial subset lets the memory bridge be exercised with ao486's actual
request generator. It is not a complete CPU import and is not part of the
production Quartus project yet. The remaining CPU and cache dependencies will
be imported during CPU integration. Keep upstream files separate from PC-98
adapters under `rtl/cpu/`.
