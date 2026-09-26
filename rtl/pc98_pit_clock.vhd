library ieee;
use ieee.std_logic_1164.all;

-- PC-98 8 MHz-family PIT input: 2.4576 MHz, independent of CPU speed.
-- Port 42h bit 5 is zero in this machine configuration. Do not pass this
-- through SFTCLK's selectable divide-by-(sel+1) stage.
entity pc98_pit_clock is
    generic(SYSFREQ : positive := 20000); -- host clock in kHz
    port(sft : out std_logic; clk, rstn : in std_logic);
end entity;
architecture rtl of pc98_pit_clock is
    constant denominator : positive := SYSFREQ * 5;
    constant increment : positive := 12288; -- 2457.6 kHz * 5
    signal phase : integer range 0 to denominator-1;
begin
    assert denominator > increment report "PIT host clock too slow" severity failure;
    process(clk,rstn) begin
        if rstn='0' then
            phase<=0;
            sft<='0';
        elsif rising_edge(clk) then
            if phase >= denominator-increment then
                phase<=phase-(denominator-increment);
                sft<='1';
            else
                phase<=phase+increment;
                sft<='0';
            end if;
        end if;
    end process;
end architecture;
