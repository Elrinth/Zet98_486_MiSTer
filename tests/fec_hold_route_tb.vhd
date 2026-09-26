library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity fec_hold_route_tb is end;
architecture test of fec_hold_route_tb is
 signal din,dout: std_logic_vector(15 downto 0);
begin
 dut: entity work.fec_hold_route_probe port map(din,dout);
 process begin
  for word in 0 to 65535 loop
   din<=std_logic_vector(to_unsigned(word,16)); wait for 1 ns;
   assert dout=std_logic_vector(to_unsigned(word,16)) report "FEC route changed payload" severity failure;
  end loop;
  report "PASS FEC route: all 65536 words, no clocked latency";
  stop; wait;
 end process;
end;
