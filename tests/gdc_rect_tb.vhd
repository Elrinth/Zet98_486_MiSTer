-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Same registered read-address latency as the production gdcfifo M9K wrapper.
entity gdcfifo is
    port(clock:in std_logic;data:in std_logic_vector(8 downto 0);
         rdaddress,wraddress:in std_logic_vector(3 downto 0);
         wren:in std_logic;q:out std_logic_vector(8 downto 0));
end;
architecture model of gdcfifo is
    type ram_t is array(0 to 15) of std_logic_vector(8 downto 0);
    signal ram:ram_t:=(others=>(others=>'0'));
    signal ra:integer range 0 to 15:=0;
begin
    process(clock) begin if rising_edge(clock) then
        ra<=to_integer(unsigned(rdaddress));
        if wren='1' then ram(to_integer(unsigned(wraddress)))<=data;end if;
    end if;end process;
    q<=ram(ra);
end;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity gdc_rect_tb is generic(ACK_DELAY:natural:=2);end;
architecture test of gdc_rect_tb is
 signal clk:std_logic:='0';signal rstn,cs,wr,rd:std_logic:='0';
 signal addr:std_logic_vector(1 downto 0):="00";
 signal din,dout:std_logic_vector(7 downto 0):=(others=>'0');
 signal b0,b1:std_logic_vector(17 downto 0);
 signal b2,b3:std_logic_vector(13 downto 0);
 signal l0,l1,l2,l3:std_logic_vector(9 downto 0);
 signal pitch:std_logic_vector(7 downto 0);
 signal zoom:std_logic_vector(3 downto 0);signal dots:std_logic_vector(4 downto 0);
 signal vs,cr,it,ge,im:std_logic;
 signal ma:std_logic_vector(17 downto 0);signal wd:std_logic_vector(15 downto 0);
 signal mr,mw,ack:std_logic:='0';signal reads,writes:natural:=0;
 type addresses is array(0 to 8191) of integer;
 signal written:addresses:=(others=>0);
begin
 clk<=not clk after 5 ns;
 dut:entity work.GRAGDC port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,DIN=>din,DOUT=>dout,DOE=>open,
 LPEND=>'0',VRTC=>'0',HRTC=>'0',VRAMSEL=>vs,CRAMSEL=>cr,INTR=>it,GRAPHEN=>ge,VZOOM=>zoom,
 BASEADDR0=>b0,BASEADDR1=>b1,SL0=>l0,SL1=>l1,BASEADDR2=>b2,BASEADDR3=>b3,
 SL2=>l2,SL3=>l3,IM=>im,PITCH=>pitch,DOTPLINE=>dots,
 GDC_ADDR=>ma,GDC_RDAT=>x"0000",GDC_WDAT=>wd,GDC_RD=>mr,GDC_WR=>mw,GDC_MACK=>ack,clk=>clk,rstn=>rstn);
 process(clk)
 variable ticks:natural:=0;variable bitno:natural;
 begin if rising_edge(clk) then
  if rstn='0' then ack<='0';ticks:=0;writes<=0;reads<=0;
  elsif mr='0' and mw='0' then ack<='0';ticks:=0;
  elsif ack='0' then
   if ticks=ACK_DELAY then
    ack<='1';
    if mr='1' then reads<=reads+1;end if;
    if mw='1' then
     assert writes<8192 report "rectangle never completes" severity failure;
     assert unsigned(wd)/=0 and (unsigned(wd) and (unsigned(wd)-1))=0
      report "rectangle must update exactly one selected pixel" severity failure;
     bitno:=0;
     for i in 0 to 15 loop
      if wd(i)='1' then bitno:=(i/8)*8+7-(i mod 8);end if;
     end loop;
     written(writes)<=to_integer(unsigned(ma))*16+bitno;writes<=writes+1;
    end if;
   else ticks:=ticks+1;end if;
  end if;
 end if;end process;
 process
 procedure cycles(n:natural) is begin for i in 1 to n loop wait until falling_edge(clk);end loop;end;
 procedure send(command:boolean;v:natural) is begin
  cs<='1';wr<='1';din<=std_logic_vector(to_unsigned(v,8));
  if command then addr<="01";else addr<="00";end if;
  cycles(2);wr<='0';cycles(16);cs<='0';
 end;
 variable dx,dy,direction,before,expected,n,stride,startaddr,startx,starty:natural;
 type steps is array(0 to 7) of integer;
 constant xs:steps:=(0,1,1,1,0,-1,-1,-1);
 constant ys:steps:=(1,1,0,-1,-1,-1,0,1);
 variable px,py,amount:integer;
 begin
  cycles(4);rstn<='1';cycles(16);
  send(true,16#78#);send(false,255);send(false,255);
  for pitchcase in 0 to 1 loop
   if pitchcase=0 then stride:=40;else stride:=160;end if;
   send(true,16#47#);send(false,stride);
   for direction0 in 0 to 7 loop
   for size in 0 to 4 loop
    if size=0 then dx:=5;dy:=3;elsif size=1 then dx:=1;dy:=1;elsif size=2 then dx:=0;dy:=3;elsif size=3 then dx:=0;dy:=0;else dx:=38;dy:=94;end if;
    -- The large case is Hunt's captured dropdown: FIGS 40h,
    -- DC=3, D=26h, D2=5Eh, CSRW=1BB9h and dot5 at pitch40.
    if size=4 then startx:=277;starty:=177;else startx:=47;starty:=10;end if;
    startaddr:=starty*stride+startx/16;
    send(true,16#49#);send(false,startaddr mod 256);send(false,startaddr/256);send(false,(startx mod 16)*16);
    send(true,16#4c#);send(false,16#40#+direction0);
    send(false,3);send(false,0);send(false,dx);send(false,0);send(false,dy);send(false,0);
    before:=writes;send(true,16#6c#);addr<="00";rd<='1';cs<='1';
    for tick in 1 to 20000 loop
     cycles(1);exit when dout(3)='0' and dout(2)='1' and tick>32;
    end loop;
    assert dout(3)='0' report "rectangle busy never clears" severity failure;
    assert writes-before=2*(dx+dy) report "rectangle pixel count incorrect" severity failure;
    px:=startx;py:=starty;n:=before;
    for side in 0 to 3 loop
     direction:=(direction0+side*2) mod 8;
     if side mod 2=0 then amount:=dx;else amount:=dy;end if;
     for pixel in 1 to amount loop
      expected:=py*stride*16+px;
      assert written(n)=expected report "rectangle wrote wrong pixel: got " & integer'image(written(n)) & " expected " & integer'image(expected) severity failure;
      px:=px+xs(direction);py:=py+ys(direction);n:=n+1;
     end loop;
    end loop;
    cs<='0';rd<='0';cycles(3);
   end loop;
  end loop;
  end loop;
  assert reads=writes report "unpaired rectangle read/write transaction" severity failure;
  report "PASS rectangle completion and pixel path, all eight directions and degenerate sides";
  finish;
 end process;
 process begin wait for 10 ms;assert false report "watchdog" severity failure;end process;
end;
