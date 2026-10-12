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
    fractional : if SYSFREQ=75000 generate
        signal phase : integer range 0 to 14;
    begin
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
    -- Any other clock (e.g. 81.818 MHz = 900 MHz / 11): a phase accumulator
    -- emits 10000 enables per SYSFREQ clocks (10 MHz average).
    accumulator : if SYSFREQ mod 10000 /= 0 and SYSFREQ/=75000 generate
        signal phase : integer range 0 to SYSFREQ+10000;
    begin
        process(clk,rstn) begin
            if rstn='0' then
                phase<=0;
                sft<='0';
            elsif rising_edge(clk) then
                if phase+10000>=SYSFREQ then
                    phase<=phase+10000-SYSFREQ;
                    sft<='1';
                else
                    phase<=phase+10000;
                    sft<='0';
                end if;
            end if;
        end process;
    end generate;
end;
