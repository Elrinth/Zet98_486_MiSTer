library ieee;
use ieee.std_logic_1164.all;

-- Preserve the legacy divider for integer multiples of 10 MHz.
-- 75 MHz needs alternating seven/eight-cycle intervals (10 MHz average).
entity opna_clock_enable is
    generic(SYSFREQ : positive := 20000);
    port(sft : out std_logic; clk, rstn : in std_logic);
end;
architecture rtl of opna_clock_enable is
begin
    integral : if SYSFREQ mod 10000 = 0 generate
        divider : entity work.sftgen generic map(SYSFREQ/10000)
            port map(SYSFREQ/10000,sft,clk,rstn);
    end generate;
    fractional : if SYSFREQ mod 10000 /= 0 generate
        signal phase : integer range 0 to 14;
    begin
        assert SYSFREQ=75000 report "Unsupported fractional OPNA clock" severity failure;
        process(clk,rstn) begin
            if rstn='0' then
                phase<=13;
                sft<='0';
            elsif rising_edge(clk) then
                if phase>=13 then
                    phase<=phase-13;
                    sft<='1';
                else
                    phase<=phase+2;
                    sft<='0';
                end if;
            end if;
        end process;
    end generate;
end;
