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
    signal load_address : std_logic_vector(19 downto 0) := (others=>'0');
    signal load_enable, load_write, font_write : std_logic := '0';
    signal font_data : std_logic_vector(7 downto 0);
    -- Text-VRAM style codes straight into the converter (right-half flags).
    signal tcode : std_logic_vector(15 downto 0) := (others=>'0');
    signal tsel : std_logic_vector(1 downto 0);
    signal taddr : std_logic_vector(16 downto 0);
begin
    tconv : entity work.knjaddrcnv port map(kcode=>tcode, cline=>"0101", mon=>open,
        romsel=>tsel, romaddr=>taddr);
    clk<=not clk after 5 ns;
    dut : entity work.KNJRAMCONT generic map(LDR_AWIDTH=>20) port map(
        LDR_ADDR=>load_address, LDR_EN=>load_enable, LDR_WR=>load_write, LDR_WDAT=>x"a5",
        ioaddr=>port_number, iowr=>wr, iord=>'0', wrdat=>value,
        KNJRAMSEL=>bank, KNJRAMADDR=>address, KNJRAMWDAT=>font_data,
        KNJRAMWR=>font_write, KNJRAMOE=>open, clk=>clk, rstn=>rstn);
    process
        variable left_sel : std_logic_vector(1 downto 0);
        variable left_addr : std_logic_vector(16 downto 0);
        procedure output(port_value, data_value : natural) is
        begin
            wait until falling_edge(clk);
            port_number<=std_logic_vector(to_unsigned(port_value,16));
            value<=std_logic_vector(to_unsigned(data_value,8)); wr<='1';
            wait until falling_edge(clk); wr<='0';
            wait until falling_edge(clk);
        end;
        variable expected_address : natural;
        type offsets_t is array(natural range <>) of natural;
        constant offsets : offsets_t := (0,1,16#1ffff#,16#20000#,16#3ffff#,16#40000#,16#467ff#);
        constant outside : offsets_t := (0,16#3ffff#,16#86800#,16#fffff#);
    begin
        wait for 27 ns; rstn<='1';
        load_enable<='1'; load_write<='1';
        for n in offsets'range loop
            load_address<=std_logic_vector(to_unsigned(16#40000#+offsets(n),20));
            wait for 1 ns;
            assert font_write='1' and font_data=x"a5" and
                to_integer(unsigned(bank))=offsets(n)/131072 and
                to_integer(unsigned(address))=offsets(n) mod 131072
                report "Font loader lost a bank boundary or the third bank" severity failure;
        end loop;
        port_number<=x"00a9"; wr<='1';
        for n in outside'range loop
            load_address<=std_logic_vector(to_unsigned(outside(n),20));
            wait for 1 ns;
            assert font_write='0' report "Font loader wrote outside FONT.ROM" severity failure;
        end loop;
        wr<='0';
        load_address<=x"80000"; load_write<='0'; wait for 1 ns;
        assert font_write='0' report "Font loader ignored its write strobe" severity failure;
        load_enable<='0'; wait for 1 ns;
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
        -- A PC-98 marks a right half in text VRAM with bit 7 of the first code
        -- byte (the low byte); this core also uses bit 15. Both must select the
        -- same right-half address, which differs from the left half and keeps
        -- the row (Flame Zapper Kotsujin's user-defined characters, row 56h).
        for row in 16#01# to 16#5d# loop
            for cell in 16#21# to 16#7e# loop
                tcode<=std_logic_vector(to_unsigned(cell*256+row,16)); wait for 1 ns;
                    left_sel:=tsel; left_addr:=taddr;
                    tcode<=std_logic_vector(to_unsigned(cell*256+row+128,16)); wait for 1 ns;
                    assert left_addr(4)='0' and taddr(4)='1' and tsel=left_sel and
                           taddr(16 downto 5)=left_addr(16 downto 5)
                        report "low-byte bit 7 right half wrong for row " & integer'image(row) &
                               " cell " & integer'image(cell) severity failure;
                    tcode<=std_logic_vector(to_unsigned(32768+cell*256+row,16)); wait for 1 ns;
                    assert taddr(4)='1' and tsel=left_sel and taddr(16 downto 5)=left_addr(16 downto 5)
                        report "bit 15 right half wrong" severity failure;
            end loop;
        end loop;
        report "PASS: text-VRAM right halves by low-byte bit 7 and by bit 15, all rows";
        report "PASS: 8192 ANK addresses and 282624 FONT.ROM addresses across 92 JIS rows";
        report "PASS: full FONT.ROM loader bank boundaries, range limits and write strobe";
        finish;
    end process;
end;
