-- SPDX-License-Identifier: GPL-3.0-or-later
-- 8253 channel 0, mode 3 (square wave), as the PC-98 BIOS interval timer uses
-- it: OUT is high for the first half of each period, so IRQ0 (rising edge)
-- comes one full period after a count is loaded. The BIOS reloads the count
-- from its callback at every tick; with OUT low-first that halved the period
-- (the NEC BIOS INT 1Ch AH=02h timer ran at 1.9x). A counter-latch command
-- must not change the mode.
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity pit_mode3_tb is end;
architecture test of pit_mode3_tb is
    signal clk:std_logic:='0'; signal rstn:std_logic:='0';
    signal cs,rd,wr:std_logic:='0';
    signal addr:std_logic_vector(1 downto 0):="00";
    signal wdat,rdat:std_logic_vector(7 downto 0):=x"00";
    signal doe:std_logic;
    signal cntin:std_logic_vector(2 downto 0):="000";
    signal cntout:std_logic_vector(2 downto 0);
    constant N:natural:=16;
begin
    clk<=not clk after 5 ns;
    dut:entity work.PTC8253 port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,RDAT=>rdat,WDAT=>wdat,DOE=>doe,
        CNTIN=>cntin,TRIG=>"000",CNTOUT=>cntout,clk=>clk,rstn=>rstn);
    process
        variable ticks, last_rise, rises : natural := 0;
        variable prev : std_logic := '0';
        procedure cycles(n:positive) is begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        procedure put(a:std_logic_vector(1 downto 0); v:std_logic_vector(7 downto 0)) is begin
            addr<=a; wdat<=v; cs<='1'; wr<='1'; cycles(1); cs<='0'; wr<='0'; cycles(2);
        end;
        procedure load is begin     -- control word 36h, count N (LSB, MSB)
            put("11",x"36"); put("00",x"10"); put("00",x"00");
        end;
        -- one PIT input clock; returns true on a rising edge of OUT0
        procedure tick(rose: out boolean) is begin
            cntin(0)<='1'; cycles(1); cntin(0)<='0'; cycles(2);
            ticks:=ticks+1;
            rose := prev='0' and cntout(0)='1';
            prev := cntout(0);
        end;
        variable r : boolean;
        variable high_run : natural := 0;
    begin
        cycles(3); rstn<='1'; cycles(3);
        load; prev:=cntout(0);
        assert cntout(0)='1' report "mode 3 OUT not high right after the count is loaded" severity failure;
        -- free running: high for N/2 inputs, then low for N/2
        for i in 1 to N/2 loop tick(r); if cntout(0)='1' then high_run:=high_run+1; end if; end loop;
        assert high_run=N/2-1 report "mode 3 first half is not high" severity failure;
        -- reload at every rising edge (BIOS callback): edges must stay N apart
        last_rise:=ticks;
        for i in 1 to 20*N loop
            tick(r);
            if r then
                rises:=rises+1;
                if rises>1 then
                    assert ticks-last_rise=N report "reloaded mode 3: IRQ edges " & integer'image(ticks-last_rise) &
                        " inputs apart, expected " & integer'image(N) severity failure;
                end if;
                last_rise:=ticks;
                load;
            end if;
        end loop;
        assert rises>=10 report "too few timer edges" severity failure;
        -- counter latch (00h) keeps mode 3: edges continue every N inputs
        put("11",x"00");
        rises:=0;
        for i in 1 to 6*N loop
            tick(r);
            if r then
                rises:=rises+1;
                if rises>1 then
                    assert ticks-last_rise=N report "period changed after a counter latch" severity failure;
                end if;
                last_rise:=ticks;
            end if;
        end loop;
        assert rises>=5 report "counter latch stopped the square wave" severity failure;
        -- BIOS INT 1Ch AH=03h: the count is rewritten (no control word) at every
        -- IRQ edge; the period must not restart, and a new count (32) applies
        -- from the next reload.
        rises:=0;
        for i in 1 to 6*N loop
            tick(r);
            if r then
                rises:=rises+1;
                if rises>1 then
                    assert ticks-last_rise=N report "count rewrite without a control word changed the period" severity failure;
                end if;
                last_rise:=ticks;
                put("00",x"10"); put("00",x"00");
            end if;
        end loop;
        put("00",x"20"); put("00",x"00");
        rises:=0;
        for i in 1 to 8*N loop
            tick(r);
            if r then
                rises:=rises+1;
                if rises=1 then
                    assert ticks-last_rise=N report "new count applied mid-period" severity failure;
                else
                    assert ticks-last_rise=2*N report "new count not applied at the reload" severity failure;
                end if;
                last_rise:=ticks;
            end if;
        end loop;
        -- Might and Magic III: at each IRQ edge the BIOS interval timer sets
        -- mode 3 (36h, count 0010h), then the music driver sets mode 0 with an
        -- MSB-only count of 0100h (20h, 01h). One rising edge per 256 inputs,
        -- none while it is being reprogrammed.
        put("11",x"36"); put("00",x"10"); put("00",x"00");
        put("11",x"20"); put("00",x"01");
        prev:=cntout(0);
        assert cntout(0)='0' report "mode 0 OUT not low after its count" severity failure;
        rises:=0; last_rise:=ticks;
        for i in 1 to 6*256 loop
            tick(r);
            if r then
                rises:=rises+1;
                assert ticks-last_rise=256 report "mode 3 -> mode 0 reprogramming: IRQ edge " &
                    integer'image(ticks-last_rise) & " inputs apart, expected 256" severity failure;
                put("11",x"36"); put("00",x"10"); put("00",x"00");
                assert cntout(0)='1' report "mode 3 control word did not keep OUT high" severity failure;
                put("11",x"20"); put("00",x"01");
                if cntout(0)='1' then
                    null;
                end if;
                prev:=cntout(0);
                last_rise:=ticks;
            end if;
        end loop;
        assert rises>=5 report "too few mode 0 edges" severity failure;
        report "PASS: 8253 mode 3 starts high, reloads keep the full period, latch keeps the mode";
        report "PASS: count rewrites apply at the next reload; control words set OUT and wait for the count (no spurious IRQ0 edge)";
        finish;
    end process;
end;
