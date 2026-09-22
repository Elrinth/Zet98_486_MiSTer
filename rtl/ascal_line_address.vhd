-- SPDX-License-Identifier: GPL-3.0-or-later
-- Scaler line-buffer read addresses, with the original one enabled cycle of
-- latency. Split the subtract into two six-bit halves; compute both upper
-- results before the low-half borrow arrives. OHRES is a power of two.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ascal_line_address is
    generic (OHRES : natural range 1 to 4096 := 2048);
    port (
        clk, ce, fraction_high : in std_logic;
        bank : in unsigned(1 downto 0);
        x, origin, delayed_origin : in natural range 0 to 4095;
        address0, address1, address2, address3 : out natural range 0 to 4095
    );
end entity;

architecture rtl of ascal_line_address is
    signal low_a, low_b : unsigned(6 downto 0);
    signal high_a, borrow_a, high_b, borrow_b : unsigned(5 downto 0);
    signal result_a, result_b : unsigned(11 downto 0);
    attribute keep : boolean;
    attribute keep of high_a, borrow_a, high_b, borrow_b : signal is true;
begin
    low_a <= ('0' & to_unsigned(x mod 64, 6)) - ('0' & to_unsigned(delayed_origin mod 64, 6));
    low_b <= ('0' & to_unsigned(x mod 64, 6)) - ('0' & to_unsigned(origin mod 64, 6));
    high_a <= to_unsigned(x / 64, 6) - to_unsigned(delayed_origin / 64, 6);
    borrow_a <= to_unsigned(x / 64, 6) - to_unsigned(delayed_origin / 64, 6) - 1;
    high_b <= to_unsigned(x / 64, 6) - to_unsigned(origin / 64, 6);
    borrow_b <= to_unsigned(x / 64, 6) - to_unsigned(origin / 64, 6) - 1;
    result_a <= high_a & low_a(5 downto 0) when low_a(6)='0' else borrow_a & low_a(5 downto 0);
    result_b <= high_b & low_b(5 downto 0) when low_b(6)='0' else borrow_b & low_b(5 downto 0);

    process(clk)
        variable first, second : natural range 0 to 4095;
    begin
        if rising_edge(clk) then
            if ce='1' then
                first := to_integer(result_a) mod OHRES;
                second := to_integer(result_b) mod OHRES;
                address0 <= first;
                address1 <= first;
                address2 <= first;
                address3 <= first;
                if fraction_high='0' then
                    case bank is
                        when "10" => address1 <= second;
                        when "11" => address2 <= second;
                        when "00" => address3 <= second;
                        when others => address0 <= second;
                    end case;
                else
                    case bank is
                        when "10" => address2 <= second;
                        when "11" => address3 <= second;
                        when "00" => address0 <= second;
                        when others => address1 <= second;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture;
