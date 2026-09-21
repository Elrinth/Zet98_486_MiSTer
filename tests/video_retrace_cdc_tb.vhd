library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity video_retrace_cdc_tb is end;
architecture test of video_retrace_cdc_tb is
    signal video_clk, cpu20, cpu40 : std_logic := '0';
    signal rstn : std_logic := '0';
    signal pixel, unused, hc, vc : std_logic;
    signal vcount : integer range 0 to 524;
    signal hcount : integer range 0 to 99;
    signal ucount : integer range 0 to 7;
    signal vraw, hraw, v20, h20, v40, h40 : std_logic;
    signal v_edges, h_edges : natural := 0;
begin
    video_clk <= not video_clk after 6667 ps;
    cpu20 <= not cpu20 after 25 ns;
    cpu40 <= not cpu40 after 12500 ps;
    timing : entity work.VTIMING port map(vcount,hcount,ucount,hc,vc,unused,pixel,video_clk,rstn);
    raster : entity work.synccont2 port map(ucount,hcount,vcount,hc,vc,open,open,open,open,hraw,vraw,pixel,rstn);
    slow : entity work.video_retrace_cdc port map(video_clk,rstn,cpu20,rstn,vraw,hraw,v20,h20);
    fast : entity work.video_retrace_cdc port map(video_clk,rstn,cpu40,rstn,vraw,hraw,v40,h40);

    -- Every real raster transition must arrive once, after bounded latency.
    -- An event-based check also rejects pulses between the expected edges.
    process
        variable expected : std_logic;
        variable edge_time : time;
    begin
        wait until rstn = '1';
        wait for 200 ns;
        loop
            wait on vraw;
            expected := vraw; edge_time := now;
            wait until v40 = expected for 80 ns;
            assert v40 = expected report "40 MHz VRTC edge lost" severity failure;
            if v20 /= expected then wait until v20 = expected for 100 ns; end if;
            assert v20 = expected and now-edge_time <= 120 ns report "20 MHz VRTC edge lost/late" severity failure;
            v_edges <= v_edges + 1;
        end loop;
    end process;
    process
        variable expected : std_logic;
        variable edge_time : time;
    begin
        wait until rstn = '1';
        wait for 200 ns;
        loop
            wait on hraw;
            expected := hraw; edge_time := now;
            wait until h40 = expected for 80 ns;
            assert h40 = expected report "40 MHz HRTC edge lost" severity failure;
            if h20 /= expected then wait until h20 = expected for 100 ns; end if;
            assert h20 = expected and now-edge_time <= 120 ns report "20 MHz HRTC edge lost/late" severity failure;
            h_edges <= h_edges + 1;
        end loop;
    end process;
    process(v20,h20) begin
        if rstn = '1' and now > 400 ns then
            assert cpu20 = '1' and cpu20'last_event = 0 ns report "20 MHz status changed outside clock edge" severity failure;
            if v20'event then assert v20 = vraw report "unexpected VRTC edge" severity failure; end if;
            if h20'event then assert h20 = hraw report "unexpected HRTC edge" severity failure; end if;
        end if;
    end process;
    process(v40,h40) begin
        if rstn = '1' and now > 400 ns then
            assert cpu40 = '1' and cpu40'last_event = 0 ns report "40 MHz status changed outside clock edge" severity failure;
            if v40'event then assert v40 = vraw report "unexpected VRTC edge" severity failure; end if;
            if h40'event then assert h40 = hraw report "unexpected HRTC edge" severity failure; end if;
        end if;
    end process;
    process begin
        wait for 177 ns; rstn <= '1';
        wait for 35 ms;
        assert v_edges >= 4 and h_edges > 2100 report "insufficient raster coverage" severity failure;
        rstn <= '0'; wait for 1 ns;
        assert (v20 & h20 & v40 & h40) = "0000" report "reset did not clear retrace status" severity failure;
        report "PASS: retrace CDC: real raster, 20/40 MHz edge counts, bounded latency, no off-clock status changes, reset";
        finish;
    end process;
end architecture;
