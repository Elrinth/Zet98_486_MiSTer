library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity peripheral_rates_tb is
    generic(FAST_KHZ : positive := 40000);
end;
architecture test of peripheral_rates_tb is
    signal clk20 : std_logic := '0';
    signal clk40 : std_logic := '0';
    signal rstn : std_logic := '0';
    signal opn20, opn40, pit20, pit40 : std_logic;
    signal start_timer : std_logic := '0';
    signal pulse20, pulse40 : std_logic;
    signal opn_count20, opn_count40, pit_count20, pit_count40 : natural := 0;
begin
    clk20 <= not clk20 after 25 ns;
    clk40 <= not clk40 after 1 ms / FAST_KHZ / 2;
    opn_base : entity work.sftgen generic map(2) port map(2, opn20, clk20, rstn);
    opn_fast : entity work.opna_clock_enable generic map(FAST_KHZ) port map(opn40, clk40, rstn);
    pit_base : entity work.sftclk generic map(20000, 2458, 1) port map("1", pit20, clk20, rstn);
    pit_fast : entity work.sftclk generic map(FAST_KHZ, 2458, 1) port map("1", pit40, clk40, rstn);
    -- The common timebase isolates pulse-width scaling from timer start delay.
    vfo_base : entity work.fixtimer generic map(200, 2)
        port map(start_timer, pit20, pulse20, clk20, rstn);
    vfo_fast : entity work.fixtimer generic map(200, 2*FAST_KHZ/20000)
        port map(start_timer, pit40, pulse40, clk40, rstn);
    process(clk20) begin
        if rising_edge(clk20) and rstn = '1' then
            if opn20 = '1' then opn_count20 <= opn_count20 + 1; end if;
            if pit20 = '1' then pit_count20 <= pit_count20 + 1; end if;
        end if;
    end process;
    process(clk40) begin
        if rising_edge(clk40) and rstn = '1' then
            if opn40 = '1' then opn_count40 <= opn_count40 + 1; end if;
            if pit40 = '1' then pit_count40 <= pit_count40 + 1; end if;
        end if;
    end process;
    process
        variable t20, t40 : time;
    begin
        wait for 200 ns;
        rstn <= '1';
        wait for 100 ns;
        start_timer <= '1';
        wait until pulse40 = '1';
        t40 := now;
        wait until pulse20 = '1';
        t20 := now;
        assert abs(t20 - t40) <= 50 ns report "VFO timer duration changed" severity failure;
        wait until pulse40 = '0';
        assert abs(now - t40 - (2*FAST_KHZ/20000)*(1 ms / FAST_KHZ)) < 1 ps report "Fast VFO pulse width changed" severity failure;
        wait until pulse20 = '0';
        assert now - t20 = 100 ns report "20 MHz VFO pulse width changed" severity failure;
        wait for 100 us;
        assert abs(integer(opn_count20) - integer(opn_count40)) <= 1
            report "OPNA clock-enable frequency changed" severity failure;
        assert abs(integer(pit_count20) - integer(pit_count40)) <= 1
            report "PIT clock-enable frequency changed" severity failure;
        report "PASS: 20 MHz / " & integer'image(FAST_KHZ) & " kHz OPNA/PIT rates and VFO pulses within one system cycle of 100 ns" severity note;
        finish;
    end process;
    process begin
        wait for 1 ms;
        assert false report "Peripheral timing watchdog" severity failure;
    end process;
end;
