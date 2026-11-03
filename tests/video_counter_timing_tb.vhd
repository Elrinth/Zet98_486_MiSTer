library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.VIDEO_TIMING_pkg.all;

-- VTIMING's raster in 400-line mode: HWIDTH pixels per line, VWIDTH400 lines.
entity video_counter_timing_tb is
    generic(RELEASE_PHASE_NS : natural := 0);
end;
architecture test of video_counter_timing_tb is
    signal clk : std_logic := '0';
    signal rstn : std_logic := '0';
    signal pixel_clk, clk2, hcomp, vcomp : std_logic;
    signal vcount : natural range 0 to VWIDTH-1;
    signal hucount : natural range 0 to HUWIDTH-1;
    signal ucount : natural range 0 to DOTPU-1;
begin
    clk <= not clk after 6667 ps;
    timing : entity work.VTIMING
        port map(vcount,hucount,ucount,hcomp,vcomp,clk2,pixel_clk,clk,rstn);
    process
        variable x : natural := 0;
        variable y : natural := VWIDTH400-1;
        variable expected_hcomp, expected_vcomp : std_logic := '0';
    begin
        wait for 100 ns + RELEASE_PHASE_NS * 1 ns;
        rstn <= '1';
        for pixel in 0 to 2*HWIDTH*VWIDTH400 loop
            -- Check exactly what downstream pixel-clocked registers sample,
            -- before any delta-cycle updates from the current rising edge.
            wait until rising_edge(pixel_clk);
            assert ucount = x mod DOTPU and hucount = x/DOTPU and vcount = y
                report "Pixel consumer sampled the wrong raster coordinate" severity failure;
            assert hcomp = expected_hcomp and vcomp = expected_vcomp
                report "Pixel consumer sampled the wrong line/frame pulse" severity failure;
            expected_hcomp := '0'; expected_vcomp := '0';
            if x = HWIDTH-1 then
                x := 0; expected_hcomp := '1';
                if y = VWIDTH400-1 then y := 0; expected_vcomp := '1';
                else y := y+1;
                end if;
            else x := x+1;
            end if;
        end loop;
        report "PASS: pixel-edge raster and line/frame pulses, reset phase " &
               integer'image(RELEASE_PHASE_NS) & " ns";
        stop;
        wait;
    end process;
end;
