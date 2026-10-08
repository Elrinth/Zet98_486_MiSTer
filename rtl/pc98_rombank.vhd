-- SPDX-License-Identifier: GPL-3.0-or-later
-- PC-9821 internal firmware-bank selector. This core has no PCI bus.
-- Bank 1 therefore supplies only an empty POST initializer (see memorymap).
-- Other banks retain the normal memory map; this is not a PCI BIOS emulator.
library ieee;
use ieee.std_logic_1164.all;

entity pc98_rombank is
    port (clk, rstn : in std_logic;
          even_address : in std_logic_vector(15 downto 0);
          rd, wr : in std_logic;
          wdata : in std_logic_vector(7 downto 0);
          rdata : out std_logic_vector(7 downto 0);
          oe, pci_bank : out std_logic);
end entity;

architecture rtl of pc98_rombank is
    signal selector : std_logic_vector(7 downto 0) := x"FE";
begin
    rdata <= selector;
    oe <= rd when even_address=x"063C" else '0';
    pci_bank <= '1' when selector(1 downto 0)="01" else '0';
    process(clk, rstn)
    begin
        if rstn='0' then
            selector <= x"FE";
        elsif rising_edge(clk) then
            if wr='1' and even_address=x"063C" then selector <= wdata; end if;
        end if;
    end process;
end architecture;
