library ieee;
use ieee.std_logic_1164.all;
use work.VIDEO_TIMING_pkg.all;
use std.env.all;

-- VTIMING frame length: 440 lines (400 visible) normally, 520 lines (480
-- visible) with MODE480. A mode change takes effect only at a frame boundary.
entity vtiming_480_tb is end;
architecture test of vtiming_480_tb is
    signal clk, rstn, mode480 : std_logic := '0';
    signal v : integer range 0 to VWIDTH-1;
    signal hu : integer range 0 to (HWIDTH/DOTPU)-1;
    signal u : integer range 0 to DOTPU-1;
    signal hcomp, vcomp, clk2, clk3 : std_logic;
    signal done : boolean := false;
begin
    dut: entity work.VTIMING generic map(VWIDTH=>VWIDTH, VVIS=>VVIS)
        port map(v,hu,u,hcomp,vcomp,clk2,clk3,clk,rstn,'0',mode480);
    clk <= not clk after 5 ns when not done else '0';
    process
        variable lines, maxv : integer;
        procedure frame(expect : integer; name : string) is
        begin
            lines := 0; maxv := 0;
            loop
                wait until rising_edge(clk3);
                if hcomp='1' then lines := lines+1; end if;
                if v>maxv then maxv := v; end if;
                exit when vcomp='1';
            end loop;
            assert lines=expect and maxv=expect-1
                report name & ": frame of " & integer'image(lines) & " lines, last line " & integer'image(maxv) severity failure;
        end procedure;
    begin
        wait for 100 ns; rstn <= '1';
        wait until rising_edge(clk3) and vcomp='1';      -- align to a frame start
        frame(VWIDTH400, "400-line frame");
        frame(VWIDTH400, "400-line frame 2");
        mode480 <= '1';                                     -- mid-frame request
        frame(VWIDTH400, "frame in progress keeps 440 lines");
        frame(VWIDTH, "480-line frame");
        frame(VWIDTH, "480-line frame 2");
        mode480 <= '0';
        frame(VWIDTH, "frame in progress keeps 520 lines");
        frame(VWIDTH400, "back to 400-line frame");
        report "PASS: VTIMING 440/520-line frames, switching only between frames";
        done <= true; finish;
    end process;
end;
