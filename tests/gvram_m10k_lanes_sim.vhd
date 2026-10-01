-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Simulation model of rtl/graphics/gvram_m10k_lanes.vhd (altsyncram):
-- eight byte lanes of 32K x 8 block RAM, zero at power-up.
-- Port A: read/write on the CPU clock (a write cycle does not update q_a).
-- Port B: display read. Both ports register the address; outputs are not registered.
entity gvram_m10k_lanes is
port(
    clk_a  : in std_logic;
    addr_a : in std_logic_vector(14 downto 0);
    we_a   : in std_logic_vector(7 downto 0);
    d_a    : in std_logic_vector(63 downto 0);
    q_a    : out std_logic_vector(63 downto 0);
    clk_b  : in std_logic;
    addr_b : in std_logic_vector(14 downto 0);
    q_b    : out std_logic_vector(63 downto 0)
);
end gvram_m10k_lanes;

architecture rtl of gvram_m10k_lanes is
begin
    lanes : for i in 0 to 7 generate
        type ram_t is array(0 to 32767) of std_logic_vector(7 downto 0);
        signal ram : ram_t := (others=>(others=>'0'));
        attribute ramstyle : string;
        attribute ramstyle of ram : signal is "M10K";
        attribute max_depth : integer;
        attribute max_depth of ram : signal is 8192;
    begin
        process(clk_a) begin
            if rising_edge(clk_a) then
                if we_a(i)='1' then
                    ram(to_integer(unsigned(addr_a))) <= d_a(i*8+7 downto i*8);
                else
                    q_a(i*8+7 downto i*8) <= ram(to_integer(unsigned(addr_a)));
                end if;
            end if;
        end process;
        process(clk_b) begin
            if rising_edge(clk_b) then
                q_b(i*8+7 downto i*8) <= ram(to_integer(unsigned(addr_b)));
            end if;
        end process;
    end generate;
end rtl;
