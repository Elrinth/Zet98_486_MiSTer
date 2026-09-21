-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;

-- The CPU selects one display page independently of the pixel address.
-- Resolve that single bit in the SDRAM clock before it drives the row mux.
-- Pixel addresses retain the existing held request/acknowledgment contract.
entity display_page_address is
    generic(FRONT_PAGE : std_logic_vector(5 downto 0) := "000100";
            BACK_PAGE : std_logic_vector(5 downto 0) := "000101");
    port(memory_clk, async_rstn, cpu_page : in std_logic;
         pixel_address : in std_logic_vector(13 downto 0);
         memory_address : out std_logic_vector(21 downto 0));
end;
architecture rtl of display_page_address is
    signal memory_rstn : std_logic;
    signal page_sync : std_logic_vector(1 downto 0);
    attribute preserve : boolean;
    attribute preserve of page_sync : signal is true;
    attribute altera_attribute : string;
    attribute altera_attribute of page_sync : signal is
        "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
begin
    display_page_reset : entity work.reset_release
        port map(memory_clk, async_rstn, memory_rstn);
    process(memory_clk, memory_rstn) begin
        if memory_rstn='0' then page_sync<="00";
        elsif rising_edge(memory_clk) then page_sync<=page_sync(0) & cpu_page;
        end if;
    end process;
    memory_address <= FRONT_PAGE & pixel_address & "00" when page_sync(1)='0'
                      else BACK_PAGE & pixel_address & "00";
end;
