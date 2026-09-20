-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quiet the PC speaker for a fixed interval after core reset. The timer runs
-- even when bypassed, so changing the menu after boot never starts a new mute.
library ieee;
use ieee.std_logic_1164.all;

entity startup_mute is
    generic (
        CLOCK_KHZ : positive := 20000;
        MUTE_MS   : natural := 10000
    );
    port (
        clk, rstn, bypass : in std_logic;
        muted : out std_logic
    );
end entity;

architecture rtl of startup_mute is
    signal tick : natural range 0 to CLOCK_KHZ - 1;
    signal elapsed_ms : natural range 0 to MUTE_MS;
begin
    process(clk, rstn)
    begin
        if rstn = '0' then
            tick <= 0;
            elapsed_ms <= 0;
        elsif rising_edge(clk) then
            if elapsed_ms < MUTE_MS then
                if tick = CLOCK_KHZ - 1 then
                    tick <= 0;
                    elapsed_ms <= elapsed_ms + 1;
                else
                    tick <= tick + 1;
                end if;
            end if;
        end if;
    end process;

    muted <= '1' when elapsed_ms < MUTE_MS and bypass = '0' else '0';
end architecture;
