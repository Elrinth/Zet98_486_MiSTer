library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.VIDEO_TIMING_pkg.all;
use std.env.all;

-- Synchronous text/attribute/font memories at the actual pixel frequency.
-- Alternating Latin and two-cell Kanji catches reuse of the previous cell's
-- RAM output, which a faster 75 MHz memory clock used to hide.
entity text_pixel_memory_tb is
    generic (RAM_DELAY_NS : natural := 12);
end;
architecture test of text_pixel_memory_tb is
    signal clk : std_logic := '0';
    signal rstn, hc, vc : std_logic := '0';
    signal u : integer range 0 to 7 := 0;
    signal hu : integer range 0 to HUWIDTH-1 := 0;
    signal v : integer range 0 to VWIDTH-1 := 0;
    signal ta : std_logic_vector(12 downto 0);
    signal td : std_logic_vector(15 downto 0) := (others=>'0');
    signal attr, fd : std_logic_vector(7 downto 0) := (others=>'0');
    signal fa : std_logic_vector(16 downto 0);
    signal fs : std_logic_vector(1 downto 0);
    signal bitout : std_logic;
    signal color : std_logic_vector(2 downto 0);
    type chars_t is array(0 to 7) of std_logic_vector(15 downto 0);
    constant chars : chars_t := (x"0041",x"2110",x"0020",x"0042",x"2350",x"0020",x"0043",x"0044");
    -- Independent known font locations for A, Kanji 2110 (both halves), B,
    -- Kanji 2350 (both halves), C, D. Right cells in TRAM deliberately contain
    -- spaces: the renderer must reuse the left cell's glyph, not those spaces.
    type bases_t is array(0 to 7) of natural;
    constant bases : bases_t := (16#0c10#,16#0cc20#,16#0cc30#,16#0c20#,
                                 16#1cc60#,16#1cc70#,16#0c30#,16#0c40#);
    function font_byte(address : natural; bank : natural) return std_logic_vector is
        variable pattern : unsigned(7 downto 0);
    begin
        pattern := to_unsigned(((address/16)*37 + (address mod 16)*19 + bank*83) mod 256,8);
        return std_logic_vector(pattern xor x"a5");
    end;
begin
    clk <= not clk after 20 ns;
    dut : entity work.KNJSCR port map(
        TRAMADR=>ta, TRAMDAT=>td, TRAMATR=>attr, FROMSEL=>fs, FROMADR=>fa, FROMDAT=>fd,
        BITOUT=>bitout, COLOR=>color,
        CURADDR=>(others=>'0'), CURE=>'0', CURUPPER=>0, CURLOWER=>15,
        CBLINK=>'0', BLINKRATE=>"01000", BASEADDR=>(others=>'0'), HMODE=>'1',
        VLINES=>"01111", PITCH=>x"50", UCOUNT=>u, HUCOUNT=>hu, VCOUNT=>v,
        HCOMP=>hc, VCOMP=>vc, clk=>clk, rstn=>rstn);

    process(clk)
        variable cell : natural;
    begin
        if rising_edge(clk) then
            cell := to_integer(unsigned(ta)) mod 8;
            td <= transport chars(cell) after RAM_DELAY_NS * 1 ns;
            -- Distinct colors, including the two halves of each Kanji. Cell 6
            -- is reversed; cell 7 has underline, testing attribute alignment.
            if cell=6 then
                attr <= transport x"c5" after RAM_DELAY_NS * 1 ns;
            elsif cell=7 then
                attr <= transport x"e9" after RAM_DELAY_NS * 1 ns;
            else
                attr <= transport std_logic_vector(to_unsigned(cell*32+1,8)) after RAM_DELAY_NS * 1 ns;
            end if;
            fd <= transport font_byte(to_integer(unsigned(fa)),to_integer(unsigned(fs))) after RAM_DELAY_NS * 1 ns;
        end if;
    end process;

    process
        variable expected : std_logic_vector(7 downto 0);
        variable cell, bank, checked : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end;
    begin
        tick; tick; rstn <= '1'; vc <= '1'; tick;
        vc <= '0'; tick; tick;
        for row in 0 to 15 loop
            v <= VIV+row;
            for unit in 0 to HIV+8 loop
                hu <= unit;
                for dot in 0 to 7 loop
                    u <= dot;
                    if unit=0 and dot=0 then hc<='1'; else hc<='0'; end if;
                    tick;
                    if unit>HIV then
                        cell := unit-HIV-1;
                        if cell=4 or cell=5 then bank:=1; else bank:=0; end if;
                        expected := font_byte(bases(cell)+row,bank);
                        if cell=6 then expected:=not expected; end if;
                        if cell=7 and row=15 then expected:=x"ff"; end if;
                        assert bitout=expected(7-dot)
                            report "Wrong text pixel: row=" & integer'image(row) &
                                " cell=" & integer'image(cell) & " dot=" & integer'image(dot)
                            severity failure;
                        assert color=std_logic_vector(to_unsigned(cell,3))
                            report "Text attribute belongs to another cell" severity failure;
                        checked := checked+1;
                    end if;
                end loop;
            end loop;
        end loop;
        report "PASS: synchronous pixel-clock text/font memories, " & integer'image(checked) & " checked pixels";
        stop; wait;
    end process;
end;
