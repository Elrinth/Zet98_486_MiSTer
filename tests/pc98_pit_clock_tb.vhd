library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity pc98_pit_clock_tb is
    generic(SYSFREQ: positive := 90000; LEGACY: boolean := false);
end;
architecture test of pc98_pit_clock_tb is
    signal clk: std_logic := '0';
    signal rstn, tick, cs, wr: std_logic := '0';
    signal addr: std_logic_vector(1 downto 0) := "00";
    signal data: std_logic_vector(7 downto 0) := x"00";
    signal countout: std_logic_vector(2 downto 0);
begin
    clk <= not clk after 5 ns;
    corrected: if not LEGACY generate
        clockgen: entity work.pc98_pit_clock generic map(SYSFREQ)
            port map(tick,clk,rstn);
    end generate;
    old_clock: if LEGACY generate
        clockgen: entity work.SFTCLK generic map(SYSFREQ,2458,1)
            port map("1",tick,clk,rstn);
    end generate;
    pit: entity work.PTC8253 port map(
        CS=>cs, ADDR=>addr, RD=>'0', WR=>wr, RDAT=>open,
        WDAT=>data, DOE=>open, CNTIN=>tick&tick&tick,
        TRIG=>"111", CNTOUT=>countout, clk=>clk, rstn=>rstn);
    process
        procedure cycle is begin wait until falling_edge(clk); end;
        procedure write_port(a: std_logic_vector(1 downto 0); d: std_logic_vector(7 downto 0)) is
        begin
            addr<=a; data<=d; cs<='1'; wr<='1';
            for i in 1 to 4 loop cycle; end loop;
            cs<='0'; wr<='0';
            for i in 1 to 4 loop cycle; end loop;
        end;
        variable ticks, edges: integer;
        variable prev: std_logic;
    begin
        for i in 1 to 4 loop cycle; end loop;
        rstn<='1'; cycle;
        -- Rusty's PDR programs timer 0 mode 3, divisor 34650/225 = 154.
        write_port("11",x"36"); write_port("00",x"9a"); write_port("00",x"00");
        for i in 1 to SYSFREQ loop cycle; end loop;
        ticks:=0; edges:=0; prev:=countout(0);
        -- 10 ms worth of host clocks: expected 24,576 PIT input strobes.
        for i in 1 to SYSFREQ*10 loop
            cycle;
            if tick='1' then ticks:=ticks+1; end if;
            if countout(0)='1' and prev='0' then edges:=edges+1; end if;
            prev:=countout(0);
        end loop;
        report "PIT host_kHz=" & integer'image(SYSFREQ) & " ticks_10ms=" & integer'image(ticks) & " PDR_IRQ_10ms=" & integer'image(edges);
        assert abs(ticks-24576)<=1 report "Wrong PIT input rate" severity failure;
        assert edges>=159 and edges<=160 report "Wrong PDR sample interrupt rate" severity failure;
        rstn<='0'; cycle; cycle;
        assert tick='0' report "PIT strobe survived reset" severity failure;
        report "PASS: accurate PIT clock and actual mode-3 sample IRQ cadence";
        finish;
    end process;
end;
