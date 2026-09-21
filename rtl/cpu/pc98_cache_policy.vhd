-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;

entity pc98_cache_policy is
    generic(UPPER_RAM_ICACHE : integer := 0);
    port(
        dma_active, load_active : in std_logic;
        cpu_address : in std_logic_vector(19 downto 1);
        cpu_write, cpu_strobe, cpu_io : in std_logic;
        odd_io_address : in std_logic_vector(15 downto 0);
        io_write : in std_logic;
        bank89, bankab : in std_logic_vector(7 downto 0);
        invalidate, upper_ram_native : out std_logic
    );
end entity;

architecture rtl of pc98_cache_policy is
    signal native89, alias_write, bank_write : std_logic;
begin
    -- Bank bit zero is not decoded by the PC-98 memory mapper.
    native89 <= '1' when UPPER_RAM_ICACHE/=0 and bank89(7 downto 1)="0000100" else '0';
    upper_ram_native <= native89;
    -- Bank changes must discard old tags and in-flight instruction prefetch.
    bank_write <= '1' when UPPER_RAM_ICACHE/=0 and io_write='1' and
        (odd_io_address=x"0461" or odd_io_address=x"0463") else '0';
    -- Direct native writes already pass through ao486's address snoop. Only
    -- aliases need a whole-cache flush, held through the entire transaction.
    alias_write <= '1' when cpu_write='1' and cpu_strobe='1' and cpu_io='0' and load_active='0' and
        ((cpu_address(19 downto 17)="100" and bank89(7 downto 3)="00000") or
         (cpu_address(19 downto 17)="101" and
           (bankab(7 downto 3)="00000" or
             (native89='1' and bankab(7 downto 1)="0000100")))) else '0';
    invalidate <= dma_active or bank_write or alias_write;
end architecture;
