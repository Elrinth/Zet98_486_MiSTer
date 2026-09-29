-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity crtc_pegc_tb is end;
architecture test of crtc_pegc_tb is
    signal clk,rstn,pixel_clk,de:std_logic:='0';signal done:boolean:=false;
    signal r,g,b:std_logic_vector(7 downto 0);
    signal text_enable,mode256:std_logic:='0';
    signal line_start,line_enable,active,page_wrap,pixel_rstn:std_logic;
    signal line_address:std_logic_vector(18 downto 3);
    signal x:std_logic_vector(9 downto 0);
    signal rgb0,rgb1,rgb2:std_logic_vector(23 downto 0);
    signal valid0,valid1:std_logic:='0';
    function color(n:natural) return std_logic_vector is
    begin return std_logic_vector(to_unsigned((n*17+91) mod 256,8)) &
                 std_logic_vector(to_unsigned((n*41+37) mod 256,8)) &
                 std_logic_vector(to_unsigned((n*71+123) mod 256,8));end;
begin
    clk<=not clk after 6667 ps when not done;
    dut:entity work.CRTC98 port map(
        TRAM_ADR=>open,TRAM_DAT=>x"0041",TRAM_ATR=>x"e1",KNJSEL=>open,KNJADR=>open,KNJDAT=>x"ff",
        GRAMADR=>open,GRAMRD=>open,GRAMACK=>'0',GRAMDAT0=>x"0000",GRAMDAT1=>x"0000",GRAMDAT2=>x"0000",GRAMDAT3=>x"0000",
        ETRAM_ADR=>open,ETRAM_DAT=>x"00",ECURL=>"00000",ECURC=>"0000000",ECUREN=>'0',
        ROUT=>open,GOUT=>open,BOUT=>open,ROUT8=>r,GOUT8=>g,BOUT8=>b,HSYNC=>open,VSYNC=>open,VIDEOEN=>de,
        TBASEADDR=>(others=>'0'),HMODE=>'1',VLINES=>"01111",TPITCH=>x"50",
        GRAPHEN=>'1',DOTPLINE=>"00000",LOWBL=>'0',GCOLOR=>'1',MONOSEL=>"0000",TXTEN=>text_enable,
        CURADDR=>(others=>'0'),CURE=>'0',CURUPPER=>0,CURLOWER=>15,CBLINK=>'0',BLINKRATE=>"01000",
        GBASEADDR0=>std_logic_vector(to_unsigned(3,14)),GBASEADDR1=>(others=>'0'),
        GLINENUM0=>std_logic_vector(to_unsigned(400,10)),GLINENUM1=>(others=>'0'),
        GBASEADDR2=>(others=>'0'),GBASEADDR3=>(others=>'0'),GLINENUM2=>(others=>'0'),GLINENUM3=>(others=>'0'),GPITCH=>x"28",
        EMUMODE=>'0',VRTC=>open,HRTC=>open,GPALNO=>open,GPALR=>x"0",GPALG=>x"0",GPALB=>x"0",
        gclk=>pixel_clk,clk=>clk,rstn=>rstn,PC_MODE=>mode256,PC_SINGLE=>'1',PC_PAGE=>'0',PC_FAST=>'0',PC_B0HI=>'1',PC_B1HI=>'0',
        PC_RGB=>rgb2,PC_VALID=>valid1,PC_LINE_START=>line_start,PC_LINE_ENABLE=>line_enable,
        PC_ACTIVE=>active,PC_PAGE_WRAP=>page_wrap,PC_RSTN=>pixel_rstn,PC_LINE_ADDRESS=>line_address,PC_X=>x);
    -- Model the independently tested line RAM (two stages) and palette (one).
    -- Every color includes lower bits that a16-color truncation would discard.
    process(pixel_clk,pixel_rstn) begin
        if pixel_rstn='0' then valid0<='0';valid1<='0';rgb0<=(others=>'0');rgb1<=(others=>'0');rgb2<=(others=>'0');
        elsif rising_edge(pixel_clk) then
            valid0<=active and line_enable;valid1<=valid0;
            rgb0<=color(to_integer(unsigned(x)));rgb1<=rgb0;rgb2<=rgb1;
        end if;
    end process;
    process
        variable count,white,rows:natural:=0;
    begin
        wait for 101 ns;rstn<='1';mode256<='1';
        wait until line_start='1' for 20 ms;
        assert line_start='1' and line_enable='1' report "packed raster not launched" severity failure;
        assert unsigned(line_address)=16#8006# and page_wrap='0' report "high SAD bit/single-page staging" severity failure;
        for y in 0 to 3 loop
            wait until de='1' for 40 us;assert de='1' report "missing DE" severity failure;
            count:=0;white:=0;
            while de='1' loop
                wait until falling_edge(pixel_clk);
                if de='1' then
                    assert not is_x(r & g & b) report "unknown packed pixel" severity failure;
                    if y=0 or y=3 then
                        assert (r & g & b)=color(count) report "packed RGB/DE latency or channel mismatch pixel=" & integer'image(count) severity failure;
                    elsif (r & g & b)=x"ffffff" then white:=white+1;end if;
                    count:=count+1;
                end if;
            end loop;
            assert count=640 report "packed visible width" severity failure;
            if y=1 or y=2 then assert white>=624 report "text overlay missing" severity failure;end if;
            if y=0 then text_enable<='1';elsif y=2 then text_enable<='0';end if;
        end loop;
        rstn<='0';wait for 1 ns;
        assert (r & g & b)=x"000000" report "packed reset left stale RGB" severity failure;
        report "PASS actual CRTC packed RGB888, high SAD bit,640pixel alignment,text overlay,reset";
        done<=true;wait;
    end process;
end;
