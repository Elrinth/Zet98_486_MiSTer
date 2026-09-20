library ieee;
use ieee.std_logic_1164.all;

-- Character scanline index. VCOUNT and HCOMP come from VTIMING; character
-- height is latched at frame start by KNJSCR. Update during horizontal blank
-- before the delayed HCOMP used for text RAM addressing and pixel fetches.
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
    rstn : in std_logic
);
end text_row_counter;

architecture rtl of text_row_counter is
    signal row : natural range 0 to 31;
begin
    process(clk, rstn) begin
        if rstn = '0' then
            row <= 0;
        elsif rising_edge(clk) then
            if vcount <= FIRST_VISIBLE_LINE then
                row <= 0;
            elsif hcomp = '1' then
                if row = char_lines-1 then
                    row <= 0;
                else
                    row <= row+1;
                end if;
            end if;
        end if;
    end process;
    row_index <= row;
end rtl;
