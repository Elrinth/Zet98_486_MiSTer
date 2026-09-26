"""Exercise the actual Quartus atom guard using recorded mapped nodes and negatives."""
from pathlib import Path
import re,sys,tkinter
script=Path('scripts/check-fec-route.tcl').read_text()
log=Path(sys.argv[1]).read_text()
nodes=[(kind,'sdramcont:ram|'+name) for kind,name in re.findall(r'^ROUTE_ATOM (\S+) (.+)$',log,re.M)]
assert len(nodes)==64
def run(items):
 t=tkinter.Tcl()
 t.eval('package provide ::quartus::project 1.0; package provide ::quartus::atoms 1.0')
 t.eval('proc project_open {args} {}; proc project_close {} {}; proc read_atom_netlist {args} {}; proc puts {args} {}')
 t.createcommand('get_atom_nodes',lambda: t.call('list',*range(len(items))))
 t.createcommand('get_atom_node_info',lambda *args: items[int(args[1])][0 if args[3]=='TYPE' else 1])
 t.eval('proc foreach_in_collection {var items body} {upvar 1 $var item; foreach item $items {uplevel 1 $body}}')
 try:t.eval(script);return None
 except tkinter.TclError as e:return str(e)
assert run(nodes) is None
cases=[('missing',nodes[:-1]),('duplicate',nodes+[nodes[0]]),('wrong type',[('FF',nodes[0][1])]+nodes[1:]),('wrong bit',[(nodes[0][0],nodes[0][1].replace('fec_hold_bits:3:','fec_hold_bits:99:'))]+nodes[1:])]
# Pick an explicitly invalid final bit without depending on atom enumeration order.
cases[-1]=('wrong bit',[(nodes[0][0],re.sub(r'fec_hold_bits:\d+:','fec_hold_bits:99:',nodes[0][1]))]+nodes[1:])
for name,items in cases:assert run(items),name
print('PASS FEC fitted-atom guard: 64 recorded mapped nodes; missing/duplicate/type/bit negatives rejected')
