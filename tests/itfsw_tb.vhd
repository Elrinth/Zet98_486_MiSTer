library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity itfsw_tb is end;
architecture test of itfsw_tb is
    signal clk : std_logic := '0';
    signal rstn, cs, wr : std_logic := '0';
    signal din : std_logic_vector(7 downto 0) := x"00";
    signal enabled : std_logic;
begin
    clk <= not clk after 5 ns;
    dut: entity work.ITFSW port map(cs, wr, din, enabled, clk, rstn);
    process
        procedure command(value : natural; selected : std_logic := '1';
                          writing : std_logic := '1') is
        begin
            wait until falling_edge(clk);
            din <= std_logic_vector(to_unsigned(value, 8));
            cs <= selected; wr <= writing;
            wait until rising_edge(clk); wait for 1 ns;
        end;
        variable expected : std_logic;
    begin
        wait for 12 ns;
        assert enabled='1' report "Reset must select ITF" severity failure;
        rstn <= '1';
        -- Exercise every command starting from both banks. Only documented
        -- aliases may change the mapping; unrelated writes must preserve it.
        for initial in 0 to 1 loop
            for value in 0 to 255 loop
                if initial=0 then command(16); expected := '1';
                else command(18); expected := '0'; end if;
                command(value);
                if value=0 or value=16 then expected := '1'; end if;
                if value=2 or value=18 then expected := '0'; end if;
                assert enabled=expected report "Wrong bank for command " &
                    integer'image(value) severity failure;
            end loop;
        end loop;
        command(16);
        command(2, '0');
        command(2, '1', '0');
        assert enabled='1' report "Unselected/read cycle changed bank" severity failure;
        command(2);
        rstn <= '0'; wait for 1 ns;
        assert enabled='1' report "Reset did not restore ITF" severity failure;
        report "ITF bank aliases PASS (512 command/state combinations)";
        stop;
        wait;
    end process;
end;
