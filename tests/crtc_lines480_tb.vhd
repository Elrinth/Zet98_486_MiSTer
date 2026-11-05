library ieee;
use ieee.std_logic_1164.all;
entity graphbuf816 is
    port(clock : in std_logic; data : in std_logic_vector(15 downto 0);
         rdaddress : in std_logic_vector(6 downto 0);
         wraddress : in std_logic_vector(5 downto 0); wren : in std_logic;
         q : out std_logic_vector(7 downto 0));
end entity;
architecture test of graphbuf816 is
begin q <= (others=>'0'); end architecture;

-- 640x480 mode: with LINES480 the CRTC shows 480 visible lines (45-524) of
-- the unchanged 800x525 raster, text rows continue to line 479, VRTC spans
-- lines 0-44, and a switch never produces a frame of mixed height.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity crtc_lines480_tb is end;
architecture test of crtc_lines480_tb is
    signal clk, raw_rstn, rstn, pixel_clk, de, vsync, vrtc : std_logic := '0';
    signal done : boolean := false;
    signal r,g,b : std_logic_vector(3 downto 0);
    signal lines480 : std_logic := '0';
begin
    process begin
        wait for 6667 ps;
        if done then wait; end if;
        clk<=not clk;
    end process;
    parent_reset : entity work.reset_release port map(clk,raw_rstn,rstn);
    dut : entity work.CRTC98 port map(
        TRAM_ADR=>open,TRAM_DAT=>x"0041",TRAM_ATR=>x"e1",
        KNJSEL=>open,KNJADR=>open,KNJDAT=>x"ff",
        GRAMADR=>open,GRAMRD=>open,GRAMACK=>'0',
        GRAMDAT0=>x"0000",GRAMDAT1=>x"0000",GRAMDAT2=>x"0000",GRAMDAT3=>x"0000",
        ETRAM_ADR=>open,ETRAM_DAT=>x"00",ECURL=>"00000",ECURC=>"0000000",ECUREN=>'0',
        ROUT=>r,GOUT=>g,BOUT=>b,HSYNC=>open,VSYNC=>vsync,VIDEOEN=>de,
        TBASEADDR=>(others=>'0'),HMODE=>'1',VLINES=>"01111",TPITCH=>x"50",
        GRAPHEN=>'0',DOTPLINE=>"00000",LOWBL=>'0',GCOLOR=>'1',MONOSEL=>"0000",TXTEN=>'1',
        CURADDR=>(others=>'0'),CURE=>'0',CURUPPER=>0,CURLOWER=>15,CBLINK=>'0',BLINKRATE=>"01000",
        GBASEADDR0=>(others=>'0'),GBASEADDR1=>(others=>'0'),
        GLINENUM0=>(others=>'0'),GLINENUM1=>(others=>'0'),GPITCH=>x"28",
        EMUMODE=>'0',VRTC=>vrtc,HRTC=>open,GPALNO=>open,GPALR=>x"0",GPALG=>x"0",GPALB=>x"0",
        gclk=>pixel_clk,clk=>clk,rstn=>rstn,LINES480=>lines480);

    process
        variable visible, white_lines, vrtc_lines, frame : natural;
        variable line_white : boolean;
        variable heights : string(1 to 6) := "      ";
        procedure measure_frame(expect : natural; tag : string) is
        begin
            -- start at a VSYNC rising edge
            wait until rising_edge(vsync);
            visible:=0;white_lines:=0;vrtc_lines:=0;
            loop
                wait until rising_edge(de) or rising_edge(vsync);
                exit when vsync='1';
                visible:=visible+1;
                line_white:=false;
                while de='1' loop
                    wait until falling_edge(pixel_clk);
                    if de='1' and (r & g & b)=x"fff" then line_white:=true; end if;
                end loop;
                if line_white then white_lines:=white_lines+1; end if;
            end loop;
            assert expect=0 or visible=expect
                report tag & ": visible lines " & integer'image(visible) severity failure;
            assert expect=0 or white_lines=visible
                report tag & ": text rows stop at " & integer'image(white_lines) severity failure;
            report "PASS " & tag & ": " & integer'image(visible) & " visible lines, text on "
                & integer'image(white_lines);
        end procedure;
    begin
        raw_rstn<='0';
        wait for 1 us;
        raw_rstn<='1';
        measure_frame(0, "settle");
        measure_frame(400, "640x400");
        -- switch in the middle of a frame: that frame keeps its height
        wait until rising_edge(de);
        lines480<='1';
        measure_frame(0, "switch frame");
        assert visible=400 or visible=480
            report "Mixed-height frame after the switch: " & integer'image(visible) severity failure;
        measure_frame(480, "640x480");
        measure_frame(480, "640x480 again");
        lines480<='0';
        measure_frame(0, "switch back");
        measure_frame(400, "640x400 again");
        done<=true;
        wait;
    end process;

    -- VRTC (vertical retrace) covers the lines before the first visible one.
    process
        variable t0 : time;
    begin
        wait until lines480='1';
        wait until rising_edge(vsync);
        wait until rising_edge(vsync);
        wait until rising_edge(vrtc);
        t0:=now;
        wait until falling_edge(vrtc);
        -- 45 lines of 32 us (800 pixels at 25 MHz) = 1.44 ms
        assert abs((now-t0)-1440 us) < 40 us
            report "VRTC width in 480-line mode: " & time'image(now-t0) severity failure;
        report "PASS VRTC spans the 45 blank lines: " & time'image(now-t0);
        wait;
    end process;

    process begin wait until done for 400 ms;assert done report "watchdog" severity failure;wait;end process;
end;
