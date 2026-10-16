-- SPDX-License-Identifier: GPL-3.0-or-later
-- PS2DIRECT (hps_io events -> KBIF-style bytes) for keyboard and mouse:
-- event byte sequences, command replies, LED mask, HOLD queueing, overflow
-- (whole sequences dropped), no replay after reset, mouse streaming gate.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity ps2direct_tb is end;
architecture test of ps2direct_tb is
 type bytes is array(natural range <>) of std_logic_vector(7 downto 0);
 signal clk:std_logic:='0';signal rstn:std_logic:='0';
 signal kin,min:std_logic_vector(7 downto 0):=x"00";
 signal kout,mout:std_logic_vector(7 downto 0);
 signal kwr,mwr:std_logic:='1';signal krx,mrx,kbusy,mbusy:std_logic;
 signal kevt,mevt:std_logic_vector(24 downto 0):=(others=>'0');
 signal khold:std_logic:='0';signal led:std_logic_vector(2 downto 0);
 signal log:bytes(0 to 31);signal n:natural:=0;signal sel_mouse:boolean:=false;signal clr:std_logic:='0';
begin
 clk<=not clk after 5 ns;
 kb:entity work.PS2DIRECT generic map(false) port map(kin,kout,kwr,kbusy,krx,kevt,khold,led,clk,rstn);
 ms:entity work.PS2DIRECT generic map(true) port map(min,mout,mwr,mbusy,mrx,mevt,'0',open,clk,rstn);
 -- Record every received byte of the device under test.
 process(clk) begin
  if rising_edge(clk) then
   if clr='1' then n<=0;
   elsif not sel_mouse and krx='1' then log(n)<=kout;n<=n+1;
   elsif sel_mouse and mrx='1' then log(n)<=mout;n<=n+1;end if;
   if sel_mouse and krx='1' then report "keyboard byte while testing the mouse" severity failure;end if;
   if not sel_mouse and mrx='1' then report "mouse byte while testing the keyboard" severity failure;end if;
  end if;
 end process;
 process
  procedure cycles(c:natural) is begin for i in 1 to c loop wait until rising_edge(clk);end loop;wait for 1 ns;end;
  procedure expect(want:bytes; what:string) is
  begin
   cycles(200);
   assert n=want'length report what & ": " & integer'image(n) & " bytes, want " & integer'image(want'length) severity failure;
   for i in want'range loop
    assert log(i-want'low)=want(i) report what & ": byte " & integer'image(i-want'low) & " = " & to_hstring(log(i-want'low)) & ", want " & to_hstring(want(i)) severity failure;
   end loop;
  end;
  procedure clear is begin cycles(200);clr<='1';cycles(1);clr<='0';end;
  procedure key(pressed,ext:std_logic; code:std_logic_vector(7 downto 0)) is
  begin kevt(10 downto 0)<=not kevt(10) & pressed & ext & code;cycles(2);end;
  procedure kcmd(b:std_logic_vector(7 downto 0)) is
  begin kin<=b;kwr<='0';cycles(1);kwr<='1';cycles(30);end;
  procedure mcmd(b:std_logic_vector(7 downto 0)) is
  begin min<=b;mwr<='0';cycles(1);mwr<='1';cycles(30);end;
  procedure mpkt(f,x,y:std_logic_vector(7 downto 0)) is
  begin mevt<=not mevt(24) & y & x & f;cycles(2);end;
 begin
  kevt(10)<='1';mevt(24)<='1';            -- toggles already set before reset
  cycles(3);rstn<='1';
  expect((0 to -1=>x"00"),"no replay after reset");
  -- Keyboard events.
  key('1','0',x"76");expect((0=>x"76"),"make");clear;
  key('0','0',x"76");expect((x"F0",x"76"),"break");clear;
  key('1','1',x"75");expect((x"E0",x"75"),"extended make");clear;
  key('0','1',x"75");expect((x"E0",x"F0",x"75"),"extended break");clear;
  -- Commands.
  kcmd(x"FF");expect((x"FA",x"AA"),"reset");clear;
  kcmd(x"F2");expect((x"FA",x"AB",x"83"),"read ID");clear;
  assert led="000" report "LED not clear" severity failure;
  kcmd(x"ED");kcmd(x"05");expect((x"FA",x"FA"),"LED command");clear;
  assert led="101" report "LED mask not latched" severity failure;
  kcmd(x"F3");kcmd(x"FF");expect((x"FA",x"FA"),"typematic argument is not a reset");clear;
  assert led="101" report "argument byte changed LEDs" severity failure;
  -- HOLD keeps bytes in order; a sequence that no longer fits is dropped whole.
  khold<='1';
  key('0','1',x"75");key('0','1',x"6B");key('0','1',x"74");
  cycles(200);assert n=0 report "byte sent while held" severity failure;
  khold<='0';
  expect((x"E0",x"F0",x"75"),"held sequence kept, later ones dropped whole");clear;
  -- A command and an event in the same cycle: neither is lost.
  kin<=x"EE";kevt(10 downto 0)<=not kevt(10) & "10" & x"1C";kwr<='0';cycles(1);kwr<='1';
  expect((x"FA",x"1C"),"simultaneous command and event");clear;
  -- Mouse.
  sel_mouse<=true;cycles(1);
  mpkt(x"08",x"10",x"10");expect((0 to -1=>x"00"),"packet before F4 is not sent");clear;
  mcmd(x"FF");expect((x"FA",x"AA",x"00"),"mouse reset");clear;
  mcmd(x"F2");expect((x"FA",x"00"),"mouse ID");clear;
  mcmd(x"F6");mcmd(x"F4");expect((x"FA",x"FA"),"defaults, enable");clear;
  mpkt(x"09",x"20",x"F0");expect((x"09",x"20",x"F0"),"mouse packet");clear;
  mcmd(x"F3");mcmd(x"F4");expect((x"FA",x"FA"),"rate argument is not a command");clear;
  mpkt(x"08",x"01",x"02");expect((x"08",x"01",x"02"),"still streaming after argument");clear;
  mcmd(x"F5");mpkt(x"08",x"01",x"02");expect((0=>x"FA"),"F5 stops the stream");clear;
  report "PASS PS2DIRECT keyboard and mouse";stop;wait;
 end process;
end;
