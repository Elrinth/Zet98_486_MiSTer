-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;

-- Assert immediately; release only after two edges in the receiving domain.
entity reset_release is
    port(clk, async_rstn : in std_logic; sync_rstn : out std_logic);
end;
architecture rtl of reset_release is
    signal stages : std_logic_vector(1 downto 0) := "00";
    attribute preserve : boolean;
    attribute preserve of stages : signal is true;
    attribute altera_attribute : string;
    attribute altera_attribute of stages : signal is
        "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
begin
    process(clk,async_rstn)
    begin
        if async_rstn='0' then stages<="00";
        elsif rising_edge(clk) then stages<=stages(0) & '1';
        end if;
    end process;
    sync_rstn<=stages(1);
end;
