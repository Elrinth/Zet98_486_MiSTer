-- Exercise the production converter, with a byte-level adapter model in
-- place of PS2DIRECT: a KEYIN bit-10 toggle injects the raw byte KEYIN(7:0),
-- so tests can open an E0/F0 sequence and finish it later. The model answers
-- commands like a keyboard and publishes HOLD (the queue-full inhibit).
library ieee;
use ieee.std_logic_1164.all;
package kbconv_model_pkg is
 signal hold_mon:std_logic:='0';
end package;
library ieee;
use ieee.std_logic_1164.all;
use work.kbconv_model_pkg.all;
entity PS2DIRECT is
 generic(MOUSE:boolean:=false);
 port(DATIN:in std_logic_vector(7 downto 0); DATOUT:out std_logic_vector(7 downto 0);
 WRn:in std_logic; BUSY,RXED:out std_logic; EVT:in std_logic_vector(24 downto 0);
 HOLD:in std_logic:='0'; LED:out std_logic_vector(2 downto 0); clk,rstn:in std_logic);
end;
architecture model of PS2DIRECT is
 signal previous_wr,previous_toggle:std_logic:='0';
 signal reply:natural range 0 to 5:=0;
 signal reply_value:std_logic_vector(7 downto 0):=x"00";
begin
 BUSY<='0';LED<="000";hold_mon<=HOLD;
 process(clk)
 begin
  if rising_edge(clk) then
   RXED<='0';previous_wr<=WRn;previous_toggle<=EVT(10);
   if rstn='0' then reply<=0;DATOUT<=x"00";previous_wr<='1';previous_toggle<=EVT(10);
   elsif WRn='0' and previous_wr='1' then
    if DATIN=x"FF" then reply_value<=x"AA";reply<=1;
    elsif DATIN=x"F2" then reply<=2;
    else reply_value<=x"FA";reply<=1;end if;
   elsif reply/=0 then
    case reply is
     when 1=>DATOUT<=reply_value;RXED<='1';reply<=0;
     when 2=>DATOUT<=x"FA";RXED<='1';reply<=3;
     when 3=>reply<=4;
     when 4=>DATOUT<=x"AB";RXED<='1';reply<=5;
     when others=>DATOUT<=x"83";RXED<='1';reply<=0;
    end case;
   elsif EVT(10)/=previous_toggle then
    DATOUT<=EVT(7 downto 0);RXED<='1';
   end if;
  end if;
 end process;
end;

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
use ieee.numeric_std.all;
use std.env.all;
use work.kbconv_model_pkg.all;
entity kbconv_backpressure_tb is generic(DELAYED_READ:boolean:=false);end;
architecture test of kbconv_backpressure_tb is
 signal clk:std_logic:='0';signal rstn:std_logic:='0';
 signal cs,addr,rd,wr:std_logic:='0';signal data:std_logic_vector(7 downto 0);
 signal oe,irq,emurx:std_logic;
 signal key:std_logic_vector(10 downto 0):=(others=>'0');signal unused1,unused2:std_logic_vector(7 downto 0);
begin
 clk<=not clk after 25 ns;
 dut:entity work.KBCONV generic map(CLKCYC=>20000,SFTCYC=>400,RPSET=>0)
 port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,RDAT=>data,WDAT=>x"00",OE=>oe,INT=>irq,
 KEYIN=>key,LEDOUT=>open,emuen=>'0',emurx=>emurx,
 emurxdat=>unused1,monout=>unused2,clk=>clk,rstn=>rstn);
 process
  procedure cycles(n:natural) is begin for i in 1 to n loop wait until rising_edge(clk);end loop;wait for 1 ns;end;
  -- One raw byte through the adapter model, 160 us apart (never simultaneous IO).
  procedure send_byte(b:std_logic_vector(7 downto 0); gap:natural:=3200) is
  begin
   key<=not key(10) & "00" & b;cycles(gap);
  end;
  procedure initialize is
  begin
   cycles(30000);
  end;
  procedure read_key(expected:std_logic_vector(7 downto 0)) is
  begin
   for i in 1 to 100 loop exit when irq='1';cycles(1);end loop;
   assert irq='1' report "pending key event missing" severity failure;
   cs<='1';addr<='0';rd<='1';cycles(3);
   report "read " & to_hstring(data) & " expected " & to_hstring(expected);
   assert data=expected report "wrong key event: " & to_hstring(data) & " expected " & to_hstring(expected) severity failure;
   rd<='0';cs<='0';cycles(1);
   assert irq='0' report "IRQ did not clear after data read" severity failure;
   cycles(8);
  end;
 begin
  cycles(5);rstn<='1';initialize;
  send_byte(x"76");
  assert irq='1' report "initial Escape make was not received (model initialization failure)" severity failure;
  if DELAYED_READ then
   send_byte(x"F0");send_byte(x"76");
   read_key(x"00");
   report "initial make survived delayed read; checking already received break";
   read_key(x"80");
   -- Hold a modifier while a complete extended arrow stroke queues up.
   send_byte(x"14");send_byte(x"E0");send_byte(x"75");
   send_byte(x"E0");send_byte(x"F0");send_byte(x"75");
   send_byte(x"F0");send_byte(x"14");
   read_key(x"74");read_key(x"3A");read_key(x"BA");read_key(x"F4");
   -- Legacy typematic semantics: repeated ordinary makes emit break/make.
   send_byte(x"76");send_byte(x"76");send_byte(x"F0");send_byte(x"76");
   read_key(x"00");read_key(x"80");read_key(x"00");read_key(x"80");
   -- Fill to the inhibit watermark (62 of 64) with 31 complete strokes. Across four
   -- rounds this also exercises pointer wrap, with no byte or prefix loss.
   for round in 1 to 4 loop
    send_byte(x"14");
    for key in 1 to 31 loop send_byte(x"F0");send_byte(x"14");end loop;
    assert hold_mon='1' report "keyboard was not inhibited at high watermark" severity failure;
    read_key(x"74");
    for key in 1 to 31 loop read_key(x"F4");end loop;
    assert hold_mon='0' report "keyboard inhibit did not release after draining" severity failure;
   end loop;
   -- Reset must discard queued bytes and pressed state, including moved pointers.
   send_byte(x"76");send_byte(x"F0");send_byte(x"76");
   rstn<='0';cycles(5);rstn<='1';initialize;
   assert irq='0' and hold_mon='0' report "stale queued event survived reset" severity failure;
   send_byte(x"76");read_key(x"00");send_byte(x"F0");send_byte(x"76");read_key(x"80");
  else
   read_key(x"00");send_byte(x"F0");send_byte(x"76");read_key(x"80");
   send_byte(x"E0");send_byte(x"75");read_key(x"3A");
   send_byte(x"E0");send_byte(x"F0");send_byte(x"75");read_key(x"BA");
   send_byte(x"14");read_key(x"74");send_byte(x"F0");send_byte(x"14");read_key(x"F4");
  end if;
  report "PASS converter make/break transport";stop;wait;
 end process;
 process begin wait for 120 ms;assert false report "keyboard test timeout" severity failure;end process;
end;
