"""Extract the actual combinational FEC route for functional/map checks."""
from pathlib import Path
import sys
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
s=Path('Zet98/sdramc.vhd').read_text()
decl=s[s.index('component LCELL is'):s.index('signal fde_write_data')]
body=s[s.index('    fec_hold_route(0) <='):s.index('    floppy_bundle :')]
assert 'for stage in 0 to 3 generate' in body and 'for bitnum in 0 to 15 generate' in body
assert 'fec_read_crossing <= fec_hold_route(4);' in body
entity='''library ieee;
use ieee.std_logic_1164.all;
entity fec_hold_route_probe is
 port(fec_read_data:in std_logic_vector(15 downto 0); fec_read_crossing:out std_logic_vector(15 downto 0));
end entity;
architecture extracted of fec_hold_route_probe is
'''+decl+'begin\n'+body+'end architecture;\n'
(out/'fec_hold_route_probe.vhd').write_text(entity)
