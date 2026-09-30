library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity crtc_compositor_tb is end;
architecture test of crtc_compositor_tb is
    signal clk : std_logic := '0';
    signal GRAPHEN, TXTEN, graphen_video, txten_video : std_logic := '0';
    signal VISIBLE, G_DOTE, T_BIT, ET_BIT, EMUMODE : std_logic := '0';
    signal TCOLOR, EF_COLOR, EB_COLOR : std_logic_vector(2 downto 0) := "000";
    signal GPALB, GPALR, GPALG, GRPHB, GRPHR, GRPHG, BOUT, ROUT, GOUT : std_logic_vector(3 downto 0);
    signal G_DOT, GPALNO : std_logic_vector(3 downto 0) := "0000";
    -- ACTIVE: inside the text GDC's programmed display area (SYNC AW/AL).
    signal ACTIVE : std_logic := '1';
    signal legacy_r, legacy_g, legacy_b : std_logic_vector(3 downto 0);
begin
    clk <= not clk after 6667 ps;
    ROUT<=legacy_r;GOUT<=legacy_g;BOUT<=legacy_b;
    GPALR<=x"3";GPALG<=x"9";GPALB<=x"c";
    process(clk) begin
        if rising_edge(clk) then graphen_video<=GRAPHEN;txten_video<=TXTEN;end if;
    end process;
    process
        variable expected : std_logic_vector(11 downto 0);
        variable old_pixel : std_logic_vector(11 downto 0);
        variable n : natural := 0;
    begin
        -- All combinations of enable/visibility/coverage and text colour.
        for mode in 0 to 511 loop
            GRAPHEN<=to_unsigned(mode,9)(0);TXTEN<=to_unsigned(mode,9)(1);
            VISIBLE<=to_unsigned(mode,9)(2);G_DOTE<=to_unsigned(mode,9)(3);
            T_BIT<=to_unsigned(mode,9)(4);TCOLOR<=std_logic_vector(to_unsigned((mode/32) mod 8,3));
            ACTIVE<=not to_unsigned(mode,9)(8);
            wait until rising_edge(clk);wait for 1 ns;
            expected:=x"000";
            if VISIBLE='1' and ACTIVE='1' then
                if TXTEN='1' and T_BIT='1' then
                    expected(11 downto 8):=(others=>TCOLOR(1));
                    expected(7 downto 4):=(others=>TCOLOR(2));
                    expected(3 downto 0):=(others=>TCOLOR(0));
                elsif GRAPHEN='1' and G_DOTE='1' then expected:=x"39c";end if;
            end if;
            assert (ROUT & GOUT & BOUT)=expected report "CRTC compositor pixel changed" severity failure;
            -- A control transition between parent edges cannot leak into RGB.
            old_pixel:=ROUT & GOUT & BOUT;
            GRAPHEN<=not GRAPHEN;TXTEN<=not TXTEN;wait for 1 ns;
            assert (ROUT & GOUT & BOUT)=old_pixel report "CPU enable bypassed video stage" severity failure;
            wait until falling_edge(clk);n:=n+1;
        end loop;
        report "PASS: CRTC final RGB gate, 512 enable/coverage/colour/active-area cases and between-edge stability";
        finish;
    end process;
    -- Runner appends the actual production compositor expressions.
end architecture;
