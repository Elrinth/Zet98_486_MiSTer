library ieee;
use ieee.std_logic_1164.all;

-- Character scanline index. VCOUNT and HCOMP come from VTIMING; character
-- height is latched at frame start by KNJSCR. Update during horizontal blank
-- before the delayed HCOMP used for text RAM addressing and pixel fetches.
--
-- CRTC smooth scroll (ports 76h SSL, 78h SUR, 7Ah SDR; NP2kai maketext): the
-- scroll region starts at the top when SUR is 0, else after 32-SUR rows, and
-- spans SDR+1 rows. Its first row starts SSL lines in, so the region moves up
-- by SSL lines. The row after the region shows its first SSL lines in the gap
-- and then starts over in full: that restart does not advance the text row.
-- Tenbu Sangokushi Seishi places its text-character mouse pointer this way
-- (SUR 0, SDR 19h, SSL 15-(y mod 16)); without it the pointer was drawn up to
-- 15 lines below its hot spot and clicks landed above the buttons. SSL values
-- of a whole row or more are ignored. The settings are taken at frame start.
-- row_advance marks a line that starts the next text row (address + pitch).
entity text_row_counter is
generic (
    FIRST_VISIBLE_LINE : natural := 125;
    TOTAL_LINES : positive := 525
);
port (
    vcount : in natural range 0 to TOTAL_LINES-1;
    hcomp : in std_logic;
    char_lines : in natural range 1 to 32;
    row_index : out natural range 0 to 31;
    clk : in std_logic;
    rstn : in std_logic;
    ssl, sur, sdr : in natural range 0 to 31 := 0;
    row_advance : out std_logic
);
end text_row_counter;

architecture rtl of text_row_counter is
    type phase_t is (ABOVE, REGION, TAIL, BELOW);
    signal phase : phase_t;
    signal row, skip, region_rows : natural range 0 to 31;
    signal rows_left : natural range 0 to 32;
    signal adv : std_logic;
begin
    process(clk, rstn)
        variable first : natural range 0 to 31;
    begin
        if rstn = '0' then
            row <= 0; adv <= '0'; skip <= 0; region_rows <= 0;
            phase <= BELOW; rows_left <= 0;
        elsif rising_edge(clk) then
            if vcount <= FIRST_VISIBLE_LINE then
                if ssl < char_lines then first := ssl; else first := 0; end if;
                skip <= first; region_rows <= sdr; adv <= '0';
                if sur = 0 then
                    phase <= REGION; rows_left <= sdr+1; row <= first;
                else
                    phase <= ABOVE; rows_left <= 32-sur; row <= 0;
                end if;
            elsif hcomp = '1' then
                adv <= '0';
                if phase = TAIL and row = skip-1 then
                    row <= 0; phase <= BELOW;
                elsif row = char_lines-1 then
                    row <= 0; adv <= '1';
                    if phase = ABOVE then
                        if rows_left = 1 then
                            phase <= REGION; rows_left <= region_rows+1; row <= skip;
                        else
                            rows_left <= rows_left-1;
                        end if;
                    elsif phase = REGION then
                        if rows_left = 1 then
                            if skip = 0 then phase <= BELOW; else phase <= TAIL; end if;
                        else
                            rows_left <= rows_left-1;
                        end if;
                    end if;
                else
                    row <= row+1;
                end if;
            end if;
        end if;
    end process;
    row_index <= row;
    row_advance <= adv;
end rtl;
