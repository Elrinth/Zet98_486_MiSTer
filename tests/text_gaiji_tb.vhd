library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.VIDEO_TIMING_pkg.all;
use std.env.all;
-- User-defined characters (rows 56h/57h) alternate halves across a run of
-- cells, left first, ignoring bit 7 (NP2kai maketext). Pac-Man (Namcot/WIZ)
-- writes each 16-dot score digit as the same code twice.
entity text_gaiji_tb is
 generic(RAM_DELAY_NS:natural:=12);
end;
architecture test of text_gaiji_tb is
 constant CELLS:natural:=12;
 type code_array is array(0 to CELLS-1) of std_logic_vector(15 downto 0);
 -- Font model: ANK=FF, left half=0F, right half=F0.
 constant CODES:code_array:=(
  x"2156", x"2156",   -- pair: L R
  x"2256", x"22d6",   -- bit 7 on the second cell does not matter: L R
  x"0041",            -- ANK ends the run
  x"23d6", x"2357",   -- bit 7 on a run's first cell still gives L, then R
  x"2156", x"2156", x"2156", -- odd run: L R L
  x"2130",            -- Kanji: L, retained right half next
  x"2156");           -- (right half of the Kanji above)
 type half_array is array(0 to CELLS-1) of std_logic_vector(7 downto 0);
 constant EXPECT:half_array:=(x"0f",x"f0",x"0f",x"f0",x"ff",x"0f",x"f0",x"0f",x"f0",x"0f",x"0f",x"f0");
 signal clk:std_logic:='0';
 signal rstn,hc,vc:std_logic:='0';
 signal u:integer range 0 to 7:=0;
 signal hu:integer range 0 to HUWIDTH-1:=0;
 signal v:integer range 0 to VWIDTH-1:=0;
 signal ta:std_logic_vector(12 downto 0);
 signal td:std_logic_vector(15 downto 0):=(others=>'0');
 signal attr,fd:std_logic_vector(7 downto 0):=x"e1";
 signal fsel:std_logic_vector(1 downto 0);
 signal fadr:std_logic_vector(16 downto 0);
 signal bitout:std_logic;
 signal color:std_logic_vector(2 downto 0);
begin
 clk<=not clk after 20 ns;
 dut:entity work.KNJSCR generic map(BLINKINT=>2) port map(
 TRAMADR=>ta,TRAMDAT=>td,TRAMATR=>attr,FROMSEL=>fsel,FROMADR=>fadr,FROMDAT=>fd,
 BITOUT=>bitout,COLOR=>color,CURADDR=>(others=>'1'),CURE=>'0',CURUPPER=>3,CURLOWER=>12,
 CBLINK=>'0',BLINKRATE=>"01000",BASEADDR=>(others=>'0'),HMODE=>'1',
 VLINES=>"01111",PITCH=>x"50",UCOUNT=>u,HUCOUNT=>hu,VCOUNT=>v,
 HCOMP=>hc,VCOMP=>vc,clk=>clk,rstn=>rstn,ATRSEL=>'0');
 process(clk)
  variable i:natural;
 begin
  if rising_edge(clk) then
   i:=to_integer(unsigned(ta));
   if i<CELLS then td<=transport CODES(i) after RAM_DELAY_NS*1 ns;
   else td<=transport x"0000" after RAM_DELAY_NS*1 ns; end if;
   attr<=transport x"e1" after RAM_DELAY_NS*1 ns;
   if fsel="00" and fadr(16 downto 11)="000001" then fd<=transport x"ff" after RAM_DELAY_NS*1 ns;
   elsif fadr(4)='1' then fd<=transport x"f0" after RAM_DELAY_NS*1 ns;
   else fd<=transport x"0f" after RAM_DELAY_NS*1 ns; end if;
  end if;
 end process;
 process
  variable checked:natural:=0;
  variable cell:integer;
  procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
 begin
  rstn<='0'; tick; tick; rstn<='1'; vc<='1'; tick; tick; vc<='0'; tick; tick;
  for row in 0 to 15 loop
   v<=VIV+row;
   for unit in 0 to HIV+CELLS+1 loop
    hu<=unit;
    for dot in 0 to 7 loop
     u<=dot;
     if unit=0 and dot=0 then hc<='1'; else hc<='0'; end if;
     tick;
     cell:=unit-HIV-1;
     if cell>=0 and cell<CELLS then
      assert bitout=EXPECT(cell)(7-dot) report "Gaiji half mismatch row="&integer'image(row)&" cell="&integer'image(cell)&" dot="&integer'image(dot) severity failure;
      checked:=checked+1;
     end if;
    end loop;
   end loop;
  end loop;
  report "PASS gaiji half alternation, bit 7 ignored, ANK and Kanji runs: "&integer'image(checked)&" pixels";
  stop; wait;
 end process;
end;
