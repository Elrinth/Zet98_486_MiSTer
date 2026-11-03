library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

-- CRTC smooth scroll (ports 76h SSL, 78h SUR, 7Ah SDR) in text_row_counter
-- against NP2kai maketext's line loop (PL 0, BL = GDC rows - 1), visible line
-- by visible line: the font line shown and the text row it comes from (the
-- count of row_advance pulses). SSL of a whole row or more is ignored by the
-- core and checked as SSL 0.
entity text_scroll_tb is end;
architecture test of text_scroll_tb is
    constant FIRST : natural := 125;
    constant TOTAL : natural := 525;
    constant NVIS : natural := TOTAL-FIRST;
    type line_array is array(0 to NVIS-1) of integer;
    signal clk : std_logic := '0';
    signal rstn, hcomp, adv : std_logic := '0';
    signal vcount : natural range 0 to TOTAL-1 := 0;
    signal char_lines : natural range 1 to 32 := 16;
    signal ssl, sur, sdr : natural range 0 to 31 := 0;
    signal row_index : natural range 0 to 31;

    -- NP2kai maketext80 (vram/maketext.c): nowline is the font line, each
    -- reload of the GDC row counter (LRcnt) moves to the next text row.
    procedure np2_frame(l, s, u, d : natural; variable lines, rows : out line_array) is
        variable nowline, wait1, wait2, lrcnt, linecnt, y : integer := 0;
        variable text_sdr : integer := -1;
        variable text_sur : integer := u;
        variable rowidx : integer := -1;
        variable reload : boolean := false;
    begin
        if u = 0 then
            wait2 := s; text_sdr := d+1;
        else
            text_sur := 32-u;
        end if;
        while y < NVIS loop
            if wait1 = 0 then
                if lrcnt = 0 then lrcnt := l-1; reload := true;
                else lrcnt := lrcnt-1; end if;
            else
                wait1 := wait1-1;
            end if;
            if reload then reload := false; rowidx := rowidx+1; end if;
            if text_sdr = 0 and nowline >= s then
                nowline := 0; text_sdr := text_sdr-1; wait1 := s;
            end if;
            if wait2 = 0 then
                lines(y) := nowline; rows(y) := rowidx; y := y+1;
            else
                wait2 := wait2-1;
            end if;
            nowline := nowline+1;
            if text_sdr /= 0 and nowline >= l then
                nowline := 0; text_sdr := text_sdr-1;
                linecnt := linecnt+1;
                if linecnt = text_sur then wait2 := s; text_sdr := d+1; end if;
            end if;
        end loop;
    end procedure;
begin
    clk <= not clk after 20 ns;
    dut : entity work.text_row_counter
        generic map(FIRST_VISIBLE_LINE=>FIRST, TOTAL_LINES=>TOTAL)
        port map(vcount=>vcount, hcomp=>hcomp, char_lines=>char_lines, row_index=>row_index,
                 clk=>clk, rstn=>rstn, ssl=>ssl, sur=>sur, sdr=>sdr, row_advance=>adv);
    process
        type nat_list is array(natural range <>) of natural;
        constant HEIGHTS : nat_list := (8, 16, 20);
        constant SSLS : nat_list := (0, 1, 3, 7, 15, 19, 20, 31);
        constant SURS : nat_list := (0, 1, 8, 20, 29, 30, 31);
        constant SDRS : nat_list := (0, 1, 5, 25, 31);
        variable exp_line, exp_row : line_array;
        variable rowidx, s_eff, checked, scrolled : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;
    begin
        tick;
        rstn <= '1';
        for h in HEIGHTS'range loop
            for a in SSLS'range loop
                for b in SURS'range loop
                    for c in SDRS'range loop
                        char_lines <= HEIGHTS(h); ssl <= SSLS(a); sur <= SURS(b); sdr <= SDRS(c);
                        s_eff := SSLS(a);
                        if s_eff >= HEIGHTS(h) then s_eff := 0; end if;
                        np2_frame(HEIGHTS(h), s_eff, SURS(b), SDRS(c), exp_line, exp_row);
                        -- Two frames each: the first also checks the change at a frame start.
                        for frame in 0 to 1 loop
                            for line in 0 to TOTAL-1 loop
                                vcount <= line;
                                hcomp <= '1';
                                tick;
                                hcomp <= '0';
                                if line >= FIRST then
                                    if line = FIRST then
                                        assert adv = '0' report "advance on the first visible line" severity failure;
                                        rowidx := 0;
                                    elsif adv = '1' then
                                        rowidx := rowidx+1;
                                    end if;
                                    assert row_index = exp_line(line-FIRST) and rowidx = exp_row(line-FIRST)
                                        report "height " & integer'image(HEIGHTS(h)) & " SSL " & integer'image(SSLS(a)) &
                                               " SUR " & integer'image(SURS(b)) & " SDR " & integer'image(SDRS(c)) &
                                               " visible line " & integer'image(line-FIRST) & ": line " &
                                               integer'image(row_index) & " row " & integer'image(rowidx) &
                                               ", NP2kai line " & integer'image(exp_line(line-FIRST)) &
                                               " row " & integer'image(exp_row(line-FIRST)) severity failure;
                                    if exp_line(line-FIRST) /= (line-FIRST) mod HEIGHTS(h) then
                                        scrolled := scrolled+1;
                                    end if;
                                    checked := checked+1;
                                end if;
                                -- HCOMP is a pulse; the outputs hold for the scanline.
                                tick;
                                assert line < FIRST or row_index = exp_line(line-FIRST)
                                    report "row changed within a scanline" severity failure;
                            end loop;
                        end loop;
                    end loop;
                end loop;
            end loop;
        end loop;
        assert scrolled > 0 report "no case moved a line" severity failure;
        report "PASS: text smooth scroll matches NP2kai, " & integer'image(checked) &
               " scanlines (" & integer'image(scrolled) & " shifted)";
        stop;
        wait;
    end process;
end test;
