library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
-- synccont2 ACTIVE: the text GDC's programmed display area (The Return of
-- Ishtar: 72 words x 384 lines) inside the 640x400 window, with VISIBLE's
-- delay. Defaults (80, 400) must equal VISIBLE exactly.
entity active_area_tb is end;
architecture test of active_area_tb is
 constant DOTPU:integer:=8; constant HWIDTH:integer:=800; constant VWIDTH:integer:=525;
 constant HFP:integer:=2; constant HSY:integer:=12; constant VFP:integer:=51; constant VSY:integer:=2;
 constant HUWIDTH:integer:=HWIDTH/DOTPU;
 constant HIV:integer:=HUWIDTH-80;               -- HFP+HSY+HBP
 constant VIV:integer:=VWIDTH-400;
 signal clk:std_logic:='0';
 signal rstn:std_logic:='0';
 signal u:integer range 0 to DOTPU-1:=0;
 signal hu:integer range 0 to HUWIDTH-1:=0;
 signal v:integer range 0 to VWIDTH-1:=0;
 signal visible,active,active_def:std_logic;
 signal actw:integer range 0 to 127:=72;
 signal actl:integer range 0 to 1023:=384;
begin
 clk<=not clk after 5 ns;
 dut:entity work.synccont2 generic map(DOTPU=>DOTPU,HWIDTH=>HWIDTH,VWIDTH=>VWIDTH,HVIS=>640,VVIS=>400,VVIS2=>480,
  CPD=>3,HFP=>HFP,HSY=>HSY,VFP=>VFP,VSY=>VSY)
  port map(u,hu,v,'0','0',open,open,visible,open,open,open,clk,rstn,actw,actl,active);
 def:entity work.synccont2 generic map(DOTPU=>DOTPU,HWIDTH=>HWIDTH,VWIDTH=>VWIDTH,HVIS=>640,VVIS=>400,VVIS2=>480,
  CPD=>3,HFP=>HFP,HSY=>HSY,VFP=>VFP,VSY=>VSY)
  port map(UCOUNT=>u,HUCOUNT=>hu,VCOUNT=>v,HCOMP=>'0',VCOMP=>'0',HSYNC=>open,VSYNC=>open,VISIBLE=>open,
   VIDEN=>open,HRTC=>open,VRTC=>open,clk=>clk,rstn=>rstn,ACTIVE=>active_def);
 process
  type hist_t is array(0 to 8) of integer;
  variable hh,vh:hist_t:=(others=>0);
  variable exp_vis,exp_act:std_logic;
  variable checked,inside:natural:=0;
 begin
  wait for 20 ns; rstn<='1';
  for line in 0 to VWIDTH-1 loop
   for unit in 0 to HUWIDTH-1 loop
    wait until falling_edge(clk);
    hu<=unit; v<=line;
    -- outputs lag the counters by nine clocks (eight-stage shift + register)
    hh:=unit & hh(0 to 7); vh:=line & vh(0 to 7);
    wait until rising_edge(clk); wait for 1 ns;
    if line>0 or unit>=9 then
     exp_vis:='0'; exp_act:='0';
     if vh(8)>=VIV and hh(8)>=HIV then
      exp_vis:='1';
      if vh(8)<VIV+384 and hh(8)<HIV+72 then exp_act:='1'; inside:=inside+1; end if;
     end if;
     assert visible=exp_vis report "VISIBLE changed" severity failure;
     assert active=exp_act report "ACTIVE mismatch at unit "&integer'image(hh(8))&" line "&integer'image(vh(8)) severity failure;
     assert active_def=visible report "default ACTIVE differs from VISIBLE" severity failure;
     checked:=checked+1;
    end if;
   end loop;
  end loop;
  assert inside=72*384 report "active area size "&integer'image(inside) severity failure;
  report "PASS active area 72x384 inside 80x400: "&integer'image(checked)&" units, "&integer'image(inside)&" active";
  stop; wait;
 end process;
end;
