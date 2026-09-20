library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity video_line_timing_tb is end;
architecture test of video_line_timing_tb is
    signal clk : std_logic := '0';
    signal rstn : std_logic := '0';
    signal pixel_clk, clk2, hcomp, vcomp : std_logic;
    signal vcount : natural range 0 to 524;
    signal hucount : natural range 0 to 99;
    signal ucount : natural range 0 to 7;
    signal char_lines : natural range 1 to 32 := 16;
    signal row_index : natural range 0 to 31;
begin
    clk <= not clk after 6667 ps;
    timing : entity work.VTIMING
        port map(vcount,hucount,ucount,hcomp,vcomp,clk2,pixel_clk,clk,rstn);
    row_count : entity work.text_row_counter
        port map(vcount,hcomp,char_lines,row_index,pixel_clk,rstn);
    process
        variable expected : natural;
        variable frame_count : natural := 0;
        variable checked : natural := 0;
    begin
        wait for 100 ns;
        rstn <= '1';
        while frame_count < 4 loop
            wait until rising_edge(pixel_clk);
            wait for 1 ns;
            if vcomp = '1' then
                frame_count := frame_count+1;
                case frame_count is
                    when 1 => char_lines <= 16;
                    when 2 => char_lines <= 20;
                    when others => char_lines <= 32;
                end case;
            end if;
            -- The actual VTIMING stages its counters onto the fast clock.
            -- The row must settle during the first character of horizontal
            -- blank, well before KNJSCR's active-text fetches at HUCOUNT >= 20.
            -- VTIMING starts on its final scanline after reset. Begin the
            -- equivalence check at the first complete frame, after VCOMP.
            if frame_count > 0 and hucount > 0 then
                if vcount < 125 then expected := 0;
                else expected := (vcount-125) mod char_lines;
                end if;
                assert row_index = expected
                    report "VTIMING/text-row phase mismatch at scanline " &
                           integer'image(vcount) severity failure;
                checked := checked+1;
            end if;
        end loop;
        report "PASS: actual VTIMING/text-row alignment, " & integer'image(checked) & " pixels";
        stop;
        wait;
    end process;
end test;
