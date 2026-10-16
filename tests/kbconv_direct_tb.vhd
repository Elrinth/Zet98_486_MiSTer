-- SPDX-License-Identifier: GPL-3.0-or-later
-- Real KBCONV through the real PS2DIRECT, driven only by hps_io ps2_key
-- events: initialisation (FF/F2/ED handshake, LEDs), make/break, extended
-- keys, and a burst that needs the FIFO and the HOLD backpressure.
library ieee;
use ieee.std_logic_1164.all;
entity SFTCLK is
 generic(SYS_CLK:integer:=20000;OUT_CLK:integer:=1600;selWIDTH:integer:=2);
 port(sel:in std_logic_vector(selWIDTH-1 downto 0);SFT:out std_logic;clk,rstn:in std_logic);
end;
architecture model of SFTCLK is begin SFT<=rstn;end;
library ieee;
use ieee.std_logic_1164.all;
entity ktbln is port(address:in std_logic_vector(7 downto 0);clock:in std_logic:='1';q:out std_logic_vector(6 downto 0));end;
architecture model of ktbln is begin
 process(clock) begin if rising_edge(clock) then
  case address is when x"76"=>q<="0000000";when x"14"=>q<="1110100";when others=>q<="1111111";end case;
 end if;end process;
end;
library ieee;
use ieee.std_logic_1164.all;
entity ktble0 is port(address:in std_logic_vector(7 downto 0);clock:in std_logic:='1';q:out std_logic_vector(6 downto 0));end;
architecture model of ktble0 is begin
 process(clock) begin if rising_edge(clock) then
  case address is when x"75"=>q<="0111010";when others=>q<="1111111";end case;
 end if;end process;
end;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity kbconv_direct_tb is end;
architecture test of kbconv_direct_tb is
 signal clk:std_logic:='0';signal rstn:std_logic:='0';
 signal cs,addr,rd:std_logic:='0';signal data:std_logic_vector(7 downto 0);
 signal irq:std_logic;signal key:std_logic_vector(10 downto 0):=(others=>'0');
 signal led:std_logic_vector(2 downto 0);
begin
 clk<=not clk after 25 ns;
 dut:entity work.KBCONV generic map(CLKCYC=>20000,SFTCYC=>400,RPSET=>0)
 port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>'0',RDAT=>data,WDAT=>x"00",OE=>open,INT=>irq,
 KEYIN=>key,LEDOUT=>led,emuen=>'0',emurx=>open,emurxdat=>open,monout=>open,clk=>clk,rstn=>rstn);
 process
  procedure cycles(n:natural) is begin for i in 1 to n loop wait until rising_edge(clk);end loop;wait for 1 ns;end;
  procedure event(pressed,ext:std_logic; code:std_logic_vector(7 downto 0)) is
  begin key<=not key(10) & pressed & ext & code;cycles(40);end;
  procedure read_key(expected:std_logic_vector(7 downto 0)) is
  begin
   for i in 1 to 400 loop exit when irq='1';cycles(1);end loop;
   assert irq='1' report "pending key event missing" severity failure;
   cs<='1';addr<='0';rd<='1';cycles(3);
   assert data=expected report "wrong key event: " & to_hstring(data) & " expected " & to_hstring(expected) severity failure;
   rd<='0';cs<='0';cycles(10);
  end;
 begin
  cycles(5);rstn<='1';cycles(30000);
  assert led="000" report "LED mask after initialisation" severity failure;
  assert irq='0' report "initialisation replies leaked to the guest" severity failure;
  event('1','0',x"76");read_key(x"00");event('0','0',x"76");read_key(x"80");
  event('1','1',x"75");read_key(x"3A");event('0','1',x"75");read_key(x"BA");
  -- Seven strokes (15 bytes) while the guest does not read: no byte, prefix or
  -- order is lost (KBCONV queue, PS2DIRECT FIFO and HOLD together).
  event('1','0',x"14");
  for k in 1 to 7 loop event('0','0',x"14");end loop;
  read_key(x"74");
  for k in 1 to 7 loop read_key(x"F4");end loop;
  cycles(400);assert irq='0' report "extra key event" severity failure;
  report "PASS KBCONV through PS2DIRECT";stop;wait;
 end process;
 process begin wait for 40 ms;assert false report "timeout" severity failure;end process;
end;
