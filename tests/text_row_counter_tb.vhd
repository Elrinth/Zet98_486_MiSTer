library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity text_row_counter_tb is end;
architecture test of text_row_counter_tb is
    signal clk : std_logic := '0';
    signal rstn, hcomp : std_logic := '0';
    signal vcount : natural range 0 to 524 := 0;
    signal char_lines : natural range 1 to 32 := 16;
    signal row_index : natural range 0 to 31;
begin
    clk <= not clk after 20 ns;
    dut : entity work.text_row_counter
        port map(vcount, hcomp, char_lines, row_index, clk, rstn);
    process
        variable expected : natural;
        variable checked : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;
    begin
        tick;
        assert row_index = 0 report "Reset did not clear row" severity failure;
        rstn <= '1';
        -- All programmable heights, changing on frame boundaries, two full
        -- frames each. Reference is the original absolute-line modulo formula.
        for height in 1 to 32 loop
            char_lines <= height;
            for frame in 0 to 1 loop
                for line in 0 to 524 loop
                    vcount <= line;
                    hcomp <= '1';
                    tick;
                    if line < 125 then expected := 0;
                    else expected := (line-125) mod height;
                    end if;
                    assert row_index = expected
                        report "Row mismatch at height " & integer'image(height) &
                               " line " & integer'image(line) severity failure;
                    hcomp <= '0';
                    -- HCOMP is a pulse, not a per-pixel enable. The index must
                    -- remain stable through the rest of the scanline.
                    for pixel in 0 to 7 loop
                        tick;
                        assert row_index = expected
                            report "Row changed within scanline" severity failure;
                    end loop;
                    checked := checked+1;
                end loop;
            end loop;
        end loop;
        rstn <= '0';
        wait for 1 ns;
        assert row_index = 0 report "Asynchronous reset failed" severity failure;
        report "PASS: text row counter, " & integer'image(checked) & " scanlines";
        stop;
        wait;
    end process;
end test;
