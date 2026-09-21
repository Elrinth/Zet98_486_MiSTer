-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
entity graphbuf816 is
    port(clock : in std_logic; data : in std_logic_vector(15 downto 0);
         rdaddress : in std_logic_vector(6 downto 0);
         wraddress : in std_logic_vector(5 downto 0); wren : in std_logic;
         q : out std_logic_vector(7 downto 0));
end entity;
architecture test of graphbuf816 is
begin q <= (others=>'0'); end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.VIDEO_TIMING_pkg.all;
entity graphics_address_tb is
    generic(REPEATS : natural := 0; FIRST_LENGTH : natural := 3;
            EXPECT_BLANK_IDLE : boolean := true);
end entity;
architecture test of graphics_address_tb is
    signal clk : std_logic := '0';
    signal rstn, rd, ack : std_logic := '0';
    signal addr : std_logic_vector(13 downto 0);
    signal uc : natural range 0 to 7 := 1;
    signal hc : natural range 0 to 99 := 0;
    signal vc : natural range 0 to 524 := 0;
    signal requests : natural := 0;
    constant BASE0 : natural := 16300;
    constant BASE1 : natural := 2048;
    constant STRIDE : natural := 43;
begin
    clk <= not clk after 20 ns;
    dut : entity work.GRAPHSCR98 port map(
        GRAMADR=>addr, GRAMRD=>rd, GRAMACK=>ack,
        GRAMDAT0=>x"0000", GRAMDAT1=>x"0000", GRAMDAT2=>x"0000", GRAMDAT3=>x"0000",
        DOTOUT=>open, DOTE=>open, GRAPHEN=>'1', BLANK=>'0',
        DOTPLINE=>std_logic_vector(to_unsigned(REPEATS,5)),
        UCOUNT=>uc, HUCOUNT=>hc, VCOUNT=>vc, HCOMP=>'0', VCOMP=>'0',
        BASEADDR0=>std_logic_vector(to_unsigned(BASE0,14)),
        BASEADDR1=>std_logic_vector(to_unsigned(BASE1,14)),
        LINENUM0=>std_logic_vector(to_unsigned(FIRST_LENGTH,10)),
        LINENUM1=>(others=>'0'), PITCH=>std_logic_vector(to_unsigned(STRIDE,8)),
        clk=>clk, rstn=>rstn);
    process(clk)
        variable word_index, logical_line, expected : natural := 0;
    begin
        if rising_edge(clk) then
            if rstn='0' then ack<='0'; requests<=0;word_index:=0;
            elsif rd='1' and ack='0' then
                if vc<VIV then
                    assert not EXPECT_BLANK_IDLE report "Graphics fetch during vertical blank" severity failure;
                else
                    assert (vc-VIV) mod (REPEATS+1)=0 report "Repeated line unnecessarily fetched" severity failure;
                    logical_line:=(vc-VIV)/(REPEATS+1);
                    if FIRST_LENGTH/=0 and logical_line>=FIRST_LENGTH then
                        expected:=(BASE1+(logical_line-FIRST_LENGTH)*STRIDE+word_index) mod 16384;
                    else expected:=(BASE0+logical_line*STRIDE+word_index) mod 16384; end if;
                    assert to_integer(unsigned(addr))=expected
                        report "Graphics address row=" & integer'image(vc-VIV) &
                            " word=" & integer'image(word_index) & " expected=" & integer'image(expected) &
                            " got=" & integer'image(to_integer(unsigned(addr))) severity failure;
                    word_index:=(word_index+1) mod 40;
                    requests<=requests+1;
                end if;
                ack<='1';
            elsif rd='0' then ack<='0'; end if;
        end if;
    end process;
    process
    begin
        wait for 201 ns; rstn<='1';
        for frame in 0 to 1 loop
            for row in 0 to 524 loop
                for pixel in 0 to 799 loop
                    wait until falling_edge(clk);
                    vc<=row;hc<=pixel/8;uc<=pixel mod 8;
                end loop;
            end loop;
        end loop;
        wait for 2 us;
        assert requests=2*((399/(REPEATS+1))+1)*40 report "Unexpected number of line reads" severity failure;
        report "PASS graphics addresses: two frames, split=" & integer'image(FIRST_LENGTH) &
            ", repeat=" & integer'image(REPEATS) & ", 14-bit wrap, no blank fetches" severity note;
        stop;wait;
    end process;
end architecture;
