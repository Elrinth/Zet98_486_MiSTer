library ieee;
use ieee.std_logic_1164.all;
use work.VIDEO_TIMING_pkg.all;
use std.env.all;

entity video_reset_tb is end;
architecture test of video_reset_tb is
    signal clk : std_logic := '0';
    signal running : boolean := true;
    signal raw_rstn, video_rstn, pixel_rstn, pixel_clk : std_logic := '0';
    signal hcomp,vcomp : std_logic;
    signal u : integer range 0 to 7;
    signal hu : integer range 0 to HUWIDTH-1;
    signal v : integer range 0 to VWIDTH-1;
begin
    process
    begin
        wait for 6667 ps;
        if running then clk<=not clk; else clk<='0'; end if;
    end process;
    video_reset : entity work.reset_release port map(clk,raw_rstn,video_rstn);
    divider : entity work.VTIMING generic map(EXTERNAL_PIXEL_RESET=>true)
        port map(v,hu,u,hcomp,vcomp,open,pixel_clk,clk,video_rstn,pixel_rstn);
    pixel_reset : entity work.reset_release port map(pixel_clk,video_rstn,pixel_rstn);
    process
        variable edges : natural := 0;
    begin
        wait on clk,raw_rstn;
        if raw_rstn='0' then edges:=0;
        elsif rising_edge(clk) and edges<2 then edges:=edges+1;
        end if;
        wait for 1 ps;
        if edges<2 then
            assert video_rstn='0' report "Video reset released before two receiving edges" severity failure;
        else
            assert video_rstn='1' report "Video reset did not release on second edge" severity failure;
        end if;
    end process;
    process
        variable edges : natural := 0;
    begin
        wait on pixel_clk,video_rstn;
        if video_rstn='0' then edges:=0;
        elsif rising_edge(pixel_clk) and edges<2 then edges:=edges+1;
        end if;
        wait for 1 ps;
        if edges<2 then
            assert pixel_rstn='0' report "Pixel reset released before two receiving edges" severity failure;
        else
            assert pixel_rstn='1' report "Pixel reset did not release on second edge" severity failure;
        end if;
    end process;
    process begin
        wait until rising_edge(pixel_clk);
        if pixel_rstn='0' then
            wait for 1 ps;
            assert u=0 and hu=0 and v=VWIDTH-1 and hcomp='0' and vcomp='0'
                report "Raster counters ran before pixel reset released" severity failure;
        end if;
    end process;
    process
    begin
        for phase in 0 to 39 loop
            raw_rstn<='0'; wait for 1 ns;
            assert video_rstn='0' and pixel_rstn='0'
                report "Reset did not assert asynchronously" severity failure;
            wait for (phase*997+17)*1 ps;
            raw_rstn<='1';
            wait until pixel_rstn='1' for 200 ns;
            assert pixel_rstn='1' report "Video/pixel reset release deadlocked" severity failure;
            wait for 200 ns;
        end loop;
        -- Reset must assert even when the destination clock is stopped, and
        -- must stay asserted if only the asynchronous source is released.
        running<=false; wait for 20 ns;
        raw_rstn<='0'; wait for 1 ns;
        assert video_rstn='0' and pixel_rstn='0' severity failure;
        raw_rstn<='1'; wait for 100 ns;
        assert video_rstn='0' and pixel_rstn='0' severity failure;
        running<=true;
        wait until pixel_rstn='1' for 200 ns;
        assert pixel_rstn='1' severity failure;
        report "PASS: video/pixel reset, 40 release phases, immediate assertion, stopped-clock recovery";
        stop; wait;
    end process;
    process begin wait for 100 us; assert false report "Reset watchdog" severity failure; end process;
end;
