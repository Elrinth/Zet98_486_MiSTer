-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.VIDEO_TIMING_pkg.all;
entity pegc_raster_tb is end;
architecture test of pegc_raster_tb is
    signal clk:std_logic:='0';signal rstn:std_logic:='0';signal done:boolean:=false;
    signal mode256,single_page,display_page,fast_clock,graph_enable:std_logic:='0';
    signal base0,base1:std_logic_vector(14 downto 0):=(others=>'0');
    signal length0,length1:std_logic_vector(9 downto 0):=(others=>'0');
    signal pitch:std_logic_vector(7 downto 0):=(others=>'0');
    signal repeat_lines:std_logic_vector(4 downto 0):=(others=>'0');
    signal hunit:integer range 0 to HUWIDTH-1:=1;
    signal dot:integer range 0 to DOTPU-1:=0;
    signal row:integer range 0 to VWIDTH-1:=0;
    signal line_start,line_enable,active,mode_pixel:std_logic;
    signal line_address:std_logic_vector(18 downto 3);
    signal pixel_x:std_logic_vector(9 downto 0);
begin
    clk<=not clk after 20 ns when not done;
    dut:entity work.pegc_raster port map(clk,rstn,mode256,single_page,display_page,fast_clock,graph_enable,
        base0,base1,length0,length1,pitch,repeat_lines,hunit,dot,row,
        line_start,line_enable,active,line_address,pixel_x,mode_pixel);
    process
        variable expected,logical_row,part_row,which,step,checks:integer:=0;
        variable a0,a1,l0,l1:integer;
    begin
        wait until falling_edge(clk);rstn<='1';mode256<='1';graph_enable<='1';
        for config in 0 to 31 loop
            a0:=(config*1043+16#7fc0#) mod 32768;a1:=(config*749+123) mod 32768;
            l0:=3+config mod 5;l1:=2+config mod 7;
            base0<=std_logic_vector(to_unsigned(a0,15));base1<=std_logic_vector(to_unsigned(a1,15));
            length0<=std_logic_vector(to_unsigned(l0,10));length1<=std_logic_vector(to_unsigned(l1,10));
            -- Packed PEGC scanout advances on every output row. The legacy
            -- CSRFORM row count is not used by NP2kai makegrex.c or MAME's
            -- pc9821_state::screen_update. Exercise all 32 possible values.
            pitch<=std_logic_vector(to_unsigned(40+config,8));repeat_lines<=std_logic_vector(to_unsigned(config,5));
            if config mod 2=0 then fast_clock<='0';step:=2*(40+config);else fast_clock<='1';step:=(40+config)/2*2;end if;
            if config mod 4<2 then single_page<='1';else single_page<='0';end if;
            if config mod 8<4 then display_page<='0';else display_page<='1';end if;
            hunit<=1;row<=0;wait until falling_edge(clk);wait until falling_edge(clk);
            for y in 0 to 399 loop
                logical_row:=y;part_row:=logical_row mod (l0+l1);
                if part_row<l0 then expected:=a0*2+part_row*step;
                else expected:=a1*2+(part_row-l0)*step;end if;
                expected:=expected mod 65536;
                if config mod 4>=2 then
                    expected:=expected mod 32768;
                    if config mod 8>=4 then expected:=expected+32768;end if;
                end if;
                hunit<=0;dot<=0;row<=VIV+y;wait for 1 ns;
                assert line_start='1' and line_enable='1' report "line launch missing" severity failure;
                assert to_integer(unsigned(line_address))=expected report "packed row address/pitch/page/repeat mismatch" severity failure;
                wait until falling_edge(clk);hunit<=HIV;wait for 1 ns;
                assert active='1' and unsigned(pixel_x)=0 report "first packed pixel" severity failure;
                hunit<=HUWIDTH-1;dot<=7;wait for 1 ns;
                assert active='1' and unsigned(pixel_x)=639 report "last packed pixel" severity failure;
                wait until falling_edge(clk);hunit<=1;dot<=0;wait until falling_edge(clk);
                checks:=checks+1;
            end loop;
        end loop;
        mode256<='0';wait until falling_edge(clk);wait until falling_edge(clk);
        assert line_enable='0' and mode_pixel='0' report "mode disable" severity failure;
        rstn<='0';wait for 1 ns;assert line_enable='0' report "reset" severity failure;
        report "PASS PEGC raster " & integer'image(checks) & " reference rows, pitch/page/wrap/partition; all 32 legacy CSRFORM counts ignored";
        done<=true;wait;
    end process;
end;
