"""Create a simulation-only dual-PIC wrapper; do not modify production RTL.

Both implementations receive identical inputs. Compare public bus data when
enabled, interrupt requests, and cascade selection every half clock cycle.
"""
from pathlib import Path
import sys

reference = Path(sys.argv[1]).read_text()
candidate = Path(sys.argv[2]).read_text()
header = reference[:reference.index('end z8259;') + len('end z8259;')]
wrapper = header + '''
architecture compare of z8259 is
 signal a_data,b_data:std_logic_vector(7 downto 0);
 signal a_oe,b_oe,a_int,b_int:std_logic;
 signal a_cas,b_cas:std_logic_vector(2 downto 0);
begin
 reference:entity work.z8259_reference generic map(monlen,RETRACTABLE_IRQS)
 port map(CS,ADDR,DIN,a_data,a_oe,RD,WR,IR0,IR1,IR2,IR3,IR4,IR5,IR6,IR7,
          a_int,INTA,CASI,a_cas,CASM,clk,rstn);
 candidate:entity work.z8259_candidate generic map(monlen,RETRACTABLE_IRQS)
 port map(CS,ADDR,DIN,b_data,b_oe,RD,WR,IR0,IR1,IR2,IR3,IR4,IR5,IR6,IR7,
          b_int,INTA,CASI,b_cas,CASM,clk,rstn);
 DOUT<=b_data;DOE<=b_oe;INT<=b_int;CASO<=b_cas;
 process begin
  wait on clk;
  wait for 1 ns;
  if rstn='1' then
   assert a_int=b_int report "PIC hold request divergence" severity failure;
   assert a_oe=b_oe report "PIC hold bus-enable divergence" severity failure;
   if a_oe='1' then
    assert a_data=b_data report "PIC hold bus-data divergence" severity failure;
   end if;
   if INTA='1' then
    assert a_cas=b_cas report "PIC hold cascade divergence" severity failure;
   end if;
  end if;
 end process;
end;
'''
Path(sys.argv[3]).write_text(
    reference.replace('z8259', 'z8259_reference') + '\n' +
    candidate.replace('z8259', 'z8259_candidate') + '\n' + wrapper)
