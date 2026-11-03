library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.VIDEO_TIMING_pkg.all;

-- VTIMING and the text row counter on the timing the core uses (the package
-- constants, as KNJSCR instantiates the counter): 440-line frames in 400-line
-- mode, 520-line frames in 480-line mode (port 09A8h), first visible line VIV.
entity video_line_timing_tb is end;
architecture test of video_line_timing_tb is
    signal clk : std_logic := '0';
    signal rstn : std_logic := '0';
    signal mode480 : std_logic := '0';
    signal pixel_clk, clk2, hcomp, vcomp : std_logic;
    signal vcount : natural range 0 to VWIDTH-1;
    signal hucount : natural range 0 to HUWIDTH-1;
    signal ucount : natural range 0 to DOTPU-1;
    signal char_lines : natural range 1 to 32 := 16;
    signal row_index : natural range 0 to 31;
begin
    clk <= not clk after 6667 ps;
    timing : entity work.VTIMING
        port map(VCOUNT=>vcount, HUCOUNT=>hucount, UCOUNT=>ucount, HCOMP=>hcomp, VCOMP=>vcomp,
                 clk2=>clk2, clk3=>pixel_clk, clk=>clk, rstn=>rstn, MODE480=>mode480);
    row_count : entity work.text_row_counter
        generic map(FIRST_VISIBLE_LINE=>VIV, TOTAL_LINES=>VWIDTH)
        port map(vcount=>vcount, hcomp=>hcomp, char_lines=>char_lines, row_index=>row_index,
                 clk=>pixel_clk, rstn=>rstn);
    process
        variable expected : natural;
        variable frame_count : natural := 0;
        variable checked, last_line : natural := 0;
    begin
        wait for 100 ns;
        rstn <= '1';
        while frame_count < 7 loop
            wait until rising_edge(pixel_clk);
            wait for 1 ns;
            if vcomp = '1' then
                frame_count := frame_count+1;
                case frame_count is
                    when 1 => char_lines <= 16;
                    when 2 => char_lines <= 20;
                    when 3 => char_lines <= 32;
                    -- 480-line frames from here on (a frame takes the mode at its start)
                    when 4 => char_lines <= 16; mode480 <= '1';
                    when others => char_lines <= 20;
                end case;
            end if;
            -- VTIMING and the text row counter share the pixel clock.
            -- The row must settle during the first character of horizontal
            -- blank, well before KNJSCR's active-text fetches at HUCOUNT >= HIV.
            -- VTIMING starts on its final scanline after reset. Begin the
            -- equivalence check at the first complete frame, after VCOMP.
            if frame_count > 0 and hucount > 0 then
                if vcount < VIV then expected := 0;
                else expected := (vcount-VIV) mod char_lines;
                end if;
                assert row_index = expected
                    report "VTIMING/text-row phase mismatch at scanline " &
                           integer'image(vcount) & " in frame " & integer'image(frame_count) severity failure;
                checked := checked+1;
                if vcount > last_line then last_line := vcount; end if;
            end if;
        end loop;
        -- Both frame lengths were scanned to their last line.
        assert last_line = VWIDTH-1 report "480-line frames never reached line " &
            integer'image(VWIDTH-1) severity failure;
        report "PASS: actual VTIMING/text-row alignment, " & integer'image(checked) &
               " pixels, 400- and 480-line frames";
        stop;
        wait;
    end process;
end test;
