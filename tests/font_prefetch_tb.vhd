-- SPDX-License-Identifier: GPL-3.0-or-later
-- Text renderer with the SDRAM font prefetch against the same renderer
-- reading the font directly (block-RAM timing): every pixel and colour of
-- several frames must agree. Text RAM holds a random mix of ANK, two-cell
-- Kanji, user-defined runs and right-half codes; the SDRAM font model
-- answers held 4-word reads after a random delay.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.VIDEO_TIMING_pkg.all;
use std.env.all;

entity font_prefetch_tb is
generic(SEED : positive := 1; VLINES : natural := 15; FRAMES : natural := 3;
        PITCHV : natural := 80; MAXDELAY : natural := 12; BREAK_FONT : boolean := false);
end font_prefetch_tb;

architecture tb of font_prefetch_tb is
    signal clk : std_logic := '0';
    signal rstn, hc, vc : std_logic := '0';
    signal u : integer range 0 to 7 := 0;
    signal hu : integer range 0 to HUWIDTH-1 := 0;
    signal v : integer range 0 to VWIDTH-1 := VWIDTH-1;
    type tram_t is array(0 to 8191) of std_logic_vector(15 downto 0);
    signal tram : tram_t;
    signal ta_r, ta_d : std_logic_vector(12 downto 0);
    signal td_r, td_d : std_logic_vector(15 downto 0) := (others=>'0');
    signal at_r, at_d, fd_r, fd_d : std_logic_vector(7 downto 0) := (others=>'0');
    signal fa_r, fa_d : std_logic_vector(16 downto 0);
    signal fs_r, fs_d : std_logic_vector(1 downto 0);
    signal b_r, b_d : std_logic;
    signal c_r, c_d : std_logic_vector(2 downto 0);
    signal fnt_adr : std_logic_vector(16 downto 0);
    signal fnt_rd, fnt_ack : std_logic := '0';
    signal fnt_dat : std_logic_vector(63 downto 0) := (others=>'0');
    signal finished : boolean := false;

    function font_byte(address : natural; bank : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(((address/16)*37 + (address mod 16)*19 + bank*83) mod 256, 8) xor x"a5");
    end function;
    function attr_of(a : std_logic_vector(12 downto 0)) return std_logic_vector is
    begin
        -- Visible, varying colour; no blink/reverse so the check stays simple.
        return std_logic_vector(to_unsigned((to_integer(unsigned(a))*5) mod 8, 3)) & "00001";
    end function;
begin
    clk <= not clk after 23 ns when not finished else '0';

    ref : entity work.KNJSCR generic map(PREFETCH=>false) port map(
        TRAMADR=>ta_r, TRAMDAT=>td_r, TRAMATR=>at_r, FROMSEL=>fs_r, FROMADR=>fa_r, FROMDAT=>fd_r,
        FNTADR=>open, FNTRD=>open,
        BITOUT=>b_r, COLOR=>c_r,
        CURADDR=>(others=>'1'), CURE=>'0', CURUPPER=>0, CURLOWER=>0, CBLINK=>'0', BLINKRATE=>"01000",
        BASEADDR=>std_logic_vector(to_unsigned(160,13)), HMODE=>'1',
        VLINES=>std_logic_vector(to_unsigned(VLINES,5)), PITCH=>std_logic_vector(to_unsigned(PITCHV,8)),
        UCOUNT=>u, HUCOUNT=>hu, VCOUNT=>v, HCOMP=>hc, VCOMP=>vc, clk=>clk, rstn=>rstn);
    dut : entity work.KNJSCR generic map(PREFETCH=>true) port map(
        TRAMADR=>ta_d, TRAMDAT=>td_d, TRAMATR=>at_d, FROMSEL=>fs_d, FROMADR=>fa_d, FROMDAT=>fd_d,
        FNTADR=>fnt_adr, FNTRD=>fnt_rd, FNTACK=>fnt_ack, FNTDAT=>fnt_dat,
        BITOUT=>b_d, COLOR=>c_d,
        CURADDR=>(others=>'1'), CURE=>'0', CURUPPER=>0, CURLOWER=>0, CBLINK=>'0', BLINKRATE=>"01000",
        BASEADDR=>std_logic_vector(to_unsigned(160,13)), HMODE=>'1',
        VLINES=>std_logic_vector(to_unsigned(VLINES,5)), PITCH=>std_logic_vector(to_unsigned(PITCHV,8)),
        UCOUNT=>u, HUCOUNT=>hu, VCOUNT=>v, HCOMP=>hc, VCOMP=>vc, clk=>clk, rstn=>rstn);

    -- Synchronous RAMs: registered address, data after the edge.
    process(clk) begin
        if rising_edge(clk) then
            td_r <= tram(to_integer(unsigned(ta_r))); at_r <= attr_of(ta_r);
            td_d <= tram(to_integer(unsigned(ta_d))); at_d <= attr_of(ta_d);
            fd_r <= font_byte(to_integer(unsigned(fa_r)), to_integer(unsigned(fs_r)));
            fd_d <= font_byte(to_integer(unsigned(fa_d)), to_integer(unsigned(fs_d)));
        end if;
    end process;

    -- SDRAM font: held 4-word read of FONT.ROM words, level acknowledge.
    process
        variable s1 : positive := SEED*11+3;
        variable s2 : positive := SEED*17+5;
        variable r : real;
        variable wa, ba : natural;
        variable d : std_logic_vector(63 downto 0);
    begin
        fnt_ack <= '0';
        loop
            wait until rising_edge(clk) and fnt_rd='1';
            uniform(s1, s2, r);
            for i in 1 to 2 + natural(floor(r*real(MAXDELAY))) loop wait until rising_edge(clk); end loop;
            wa := to_integer(unsigned(fnt_adr(15 downto 0)));
            for i in 0 to 3 loop
                ba := (wa+i)*2;
                if BREAK_FONT and i=3 then ba := ba + 1; end if;
                d(i*16+7 downto i*16) := font_byte(ba mod 131072, to_integer(unsigned'('0' & fnt_adr(16))));
                d(i*16+15 downto i*16+8) := font_byte((ba+1) mod 131072, to_integer(unsigned'('0' & fnt_adr(16))));
            end loop;
            fnt_dat <= d; fnt_ack <= '1';
            wait until rising_edge(clk) and fnt_rd='0';
            fnt_ack <= '0';
        end loop;
    end process;

    process
        variable s1 : positive := SEED*7+1;
        variable s2 : positive := SEED*13+2;
        variable r : real;
        variable t : tram_t;
        variable k : natural;
        impure function rnd(n : natural) return natural is
        begin uniform(s1, s2, r); return natural(floor(r*real(n))) mod n; end function;
    begin
        for i in 0 to 8191 loop
            case rnd(8) is
            when 0 | 1 | 2 => t(i) := x"00" & std_logic_vector(to_unsigned(rnd(256), 8));        -- ANK
            when 3 | 4 =>     -- two-cell Kanji, JIS row 21h-4Fh and 50h-55h style codes
                k := 16#10# + rnd(16#46#);
                t(i) := std_logic_vector(to_unsigned(16#21# + rnd(94), 8)) & std_logic_vector(to_unsigned(k, 8));
            when 5 =>         -- user-defined row 56h/57h, either bit 7
                t(i) := std_logic_vector(to_unsigned(16#21# + rnd(94), 8)) &
                        std_logic_vector(to_unsigned(16#56# + rnd(2) + 128*rnd(2), 8));
            when 6 =>         -- explicit right half
                t(i) := std_logic_vector(to_unsigned(16#a1# + rnd(94), 8)) & std_logic_vector(to_unsigned(16#21# + rnd(16#30#), 8));
            when others =>    -- semigraphics / odd rows
                t(i) := std_logic_vector(to_unsigned(1 + rnd(255), 8)) & std_logic_vector(to_unsigned(rnd(16#0e#), 8));
            end case;
        end loop;
        tram <= t;
        wait;
    end process;

    -- Raster counters as VTIMING: HCOMP/VCOMP with the new line/frame.
    process
        variable checked, nfr : natural := 0;
    begin
        rstn <= '0';
        for i in 1 to 4 loop wait until rising_edge(clk); end loop;
        rstn <= '1';
        while nfr < FRAMES loop
            wait until rising_edge(clk);
            hc <= '0'; vc <= '0';
            if nfr>=2 or (nfr=1 and v>=VIV) then
                assert b_r=b_d and c_r=c_d report "Prefetched text differs: line " & integer'image(v) &
                    " unit " & integer'image(hu) & " dot " & integer'image(u) severity failure;
                if b_r='1' then checked := checked+1; end if;
            end if;
            if u=7 then
                u <= 0;
                if hu=HUWIDTH-1 then
                    hu <= 0; hc <= '1';
                    if v=VWIDTH-1 then v <= 0; vc <= '1'; nfr := nfr+1;
                    else v <= v+1; end if;
                else hu <= hu+1; end if;
            else u <= u+1; end if;
        end loop;
        report "PASS font prefetch seed " & integer'image(SEED) & " lines " & integer'image(VLINES+1) &
            ", " & integer'image(checked) & " lit pixels compared";
        finished <= true;
        wait;
    end process;
end tb;
