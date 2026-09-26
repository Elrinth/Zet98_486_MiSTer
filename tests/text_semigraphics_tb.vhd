library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.VIDEO_TIMING_pkg.all;
use std.env.all;
entity text_semigraphics_tb is
 generic(HEIGHT:positive:=16; WIDE:boolean:=false; RAM_DELAY_NS:natural:=12);
end;
architecture test of text_semigraphics_tb is
 signal clk:std_logic:='0';
 signal rstn,hc,vc,mode,cure:std_logic:='0';
 signal hm:std_logic;
 signal u:integer range 0 to 7:=0;
 signal hu:integer range 0 to HUWIDTH-1:=0;
 signal v:integer range 0 to VWIDTH-1:=0;
 signal ta:std_logic_vector(12 downto 0);
 signal code,td:std_logic_vector(15 downto 0):=(others=>'0');
 signal attr_cfg,attr,fd:std_logic_vector(7 downto 0):=x"f1";
 signal bitout:std_logic;
 signal color:std_logic_vector(2 downto 0);
begin
 clk<=not clk after 20 ns;
 hm<='0' when WIDE else '1';
 dut:entity work.KNJSCR generic map(BLINKINT=>2) port map(
 TRAMADR=>ta,TRAMDAT=>td,TRAMATR=>attr,FROMSEL=>open,FROMADR=>open,FROMDAT=>fd,
 BITOUT=>bitout,COLOR=>color,CURADDR=>(others=>'0'),CURE=>cure,CURUPPER=>3,CURLOWER=>12,
 CBLINK=>'0',BLINKRATE=>"01000",BASEADDR=>(others=>'0'),HMODE=>hm,
 VLINES=>std_logic_vector(to_unsigned(HEIGHT-1,5)),PITCH=>x"50",UCOUNT=>u,HUCOUNT=>hu,VCOUNT=>v,
 HCOMP=>hc,VCOMP=>vc,clk=>clk,rstn=>rstn,ATRSEL=>mode);
 process(clk) begin
  if rising_edge(clk) then
   td<=transport code after RAM_DELAY_NS*1 ns;
   attr<=transport attr_cfg after RAM_DELAY_NS*1 ns;
   fd<=transport x"5a" after RAM_DELAY_NS*1 ns;
  end if;
 end process;
 process
  variable expected:std_logic_vector(7 downto 0);
  variable pat:unsigned(7 downto 0);
  variable a:std_logic_vector(7 downto 0);
  variable idx,checked:natural:=0;
  procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
 begin
  -- Exhaustive glyphs, then attribute, ordinary-line, font and Kanji controls.
  for trial in 0 to 266 loop
   rstn<='0'; vc<='0'; hc<='0'; u<=0; hu<=0; v<=0;
   tick; tick;
   mode<='1'; cure<='0'; code<=std_logic_vector(to_unsigned(trial mod 256,16)); a:=x"f1";
   case trial is
    when 256 => code<=x"0000"; mode<='0'; -- ordinary vertical line retained
    when 257 => code<=x"00ff"; a:=x"e1"; -- bit4 clear: ROM glyph
    when 258 => code<=x"2110"; -- Kanji wins even with semigraphics attribute
    when 259 => code<=x"00ff"; a:=x"f0"; -- secret
    when 260 => code<=x"00ff"; a:=x"f3"; -- blink hidden
    when 261 => code<=x"0000"; a:=x"f5"; -- reverse
    when 262 => code<=x"0000"; a:=x"f9"; -- underline
    when 263 => code<=x"0000"; cure<='1'; -- cursor
    when 264 => code<=x"0000"; mode<='0'; -- live mode changes below
    when 265 => code<=x"0000"; -- clear after reset
    when 266 => code<=x"2110"; mode<='0'; -- Kanji normal vertical-line mode
    when others => null;
   end case;
   attr_cfg<=a; rstn<='1'; vc<='1'; tick; tick; vc<='0'; tick; tick;
   for row in 0 to HEIGHT-1 loop
    v<=VIV+row;
    if trial=264 then
     if (row mod 2)=0 then mode<='1'; else mode<='0'; end if;
    end if;
    for unit in 0 to HIV+2 loop
     hu<=unit;
     for dot in 0 to 7 loop
      u<=dot;
      if unit=0 and dot=0 then hc<='1'; else hc<='0'; end if;
      tick;
      if unit=HIV+1 or (WIDE and unit=HIV+2) then
       expected:=x"00";
       if trial<256 then
        -- Spatial reference: each code bit lights a rectangle, independent of ROM.
        pat:=to_unsigned(trial,8);
        for x in 0 to 7 loop
         idx:=(row*4)/HEIGHT;
         if x>=4 then idx:=idx+4; end if;
         expected(7-x):=pat(idx);
        end loop;
       elsif trial=256 or trial=266 or (trial=264 and (row mod 2)=1) then
        expected:=x"5a"; expected(3):='1';
       elsif trial=257 or trial=258 then expected:=x"5a";
       elsif trial=261 then expected:=x"ff";
       elsif trial=262 and row=15 then expected:=x"ff";
       elsif trial=263 and row>3 and row<12 then expected:=x"ff";
       end if;
       idx:=dot;
       if WIDE then idx:=((unit-HIV-1)*8+dot)/2; end if;
       assert bitout=expected(7-idx) report "Semigraphics pixel mismatch trial="&integer'image(trial)&" row="&integer'image(row)&" dot="&integer'image(idx) severity failure;
       assert color="111" report "Semigraphics color mismatch" severity failure;
       checked:=checked+1;
      end if;
     end loop;
    end loop;
   end loop;
  end loop;
  report "PASS semigraphics, ordinary lines, attributes, Kanji, mode changes: "&integer'image(checked)&" pixels";
  stop; wait;
 end process;
end;
