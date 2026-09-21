library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity font_address_tb is end;
architecture test of font_address_tb is
    signal clk : std_logic := '0';
    signal rstn, wr : std_logic := '0';
    signal port_number : std_logic_vector(15 downto 0) := (others=>'0');
    signal value : std_logic_vector(7 downto 0) := (others=>'0');
    signal bank : std_logic_vector(1 downto 0);
    signal address : std_logic_vector(16 downto 0);
begin
    clk<=not clk after 5 ns;
    dut : entity work.KNJRAMCONT port map(
        LDR_ADDR=>(others=>'0'), LDR_EN=>'0', LDR_WR=>'0', LDR_WDAT=>x"00",
        ioaddr=>port_number, iowr=>wr, iord=>'0', wrdat=>value,
        KNJRAMSEL=>bank, KNJRAMADDR=>address, KNJRAMWDAT=>open,
        KNJRAMWR=>open, KNJRAMOE=>open, clk=>clk, rstn=>rstn);
    process
        procedure output(port_value, data_value : natural) is
        begin
            wait until falling_edge(clk);
            port_number<=std_logic_vector(to_unsigned(port_value,16));
            value<=std_logic_vector(to_unsigned(data_value,8)); wr<='1';
            wait until falling_edge(clk); wr<='0';
            wait until falling_edge(clk);
        end;
        variable expected_address : natural;
    begin
        wait for 27 ns; rstn<='1';
        output(16#a1#,0);
        -- The first letter of Rusty's Start menu, with the normal line selector.
        output(16#a3#,character'pos('S')); output(16#a5#,0);
        assert bank="00" and unsigned(address)=16#800#+16*character'pos('S')
            report "ASCII font read selected a Kanji glyph for Start" severity failure;
        -- Rusty's English title menu uses character S in JIS row 09,
        -- reached through A1=53, A3=09, A5=20 (left glyph half).
        output(16#a1#,character'pos('S')); output(16#a3#,9); output(16#a5#,32);
        assert bank="00" and unsigned(address)=16#7e60#
            report "Rusty row09 S selected the wrong FONT.ROM glyph" severity failure;
        output(16#a1#,0);
        for code in 0 to 255 loop
            output(16#a3#,code);
            for half in 0 to 1 loop
                for row in 0 to 15 loop
                    output(16#a5#,half*32+row);
                    assert bank="00" and unsigned(address)=16#800#+code*16+row
                        report "ASCII font depends on Kanji left/right selector" severity failure;
                end loop;
            end loop;
        end loop;
        -- Independent FONT.ROM layout: 0x1800-byte ANK area, then 92 rows
        -- of 96 glyphs, each holding the 16 left bytes and 16 right bytes.
        for jis_row in 1 to 92 loop
            output(16#a3#,jis_row);
            for code in 32 to 127 loop
                output(16#a1#,code);
                for half in 0 to 1 loop
                    for row in 0 to 15 loop
                        output(16#a5#,half*32+row);
                        expected_address:=16#1800#+(jis_row-1)*96*32+
                            (code-32)*32+(1-half)*16+row;
                        assert to_integer(unsigned(bank))*131072+to_integer(unsigned(address))=expected_address
                            report "FONT.ROM mapping mismatch at JIS row " & integer'image(jis_row) &
                                " character " & integer'image(code) & " half " & integer'image(half)
                            severity failure;
                    end loop;
                end loop;
            end loop;
        end loop;
        report "PASS: 8192 ANK addresses and 282624 FONT.ROM addresses across 92 JIS rows";
        finish;
    end process;
end;
