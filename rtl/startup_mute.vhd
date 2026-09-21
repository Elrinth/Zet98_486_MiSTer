-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quiet the PC speaker after core reset. Never expose the tail of a boot beep
-- that is still active when the minimum interval expires. The timer runs even
-- when bypassed, so changing the menu after boot never starts a new mute.
library ieee;
use ieee.std_logic_1164.all;

entity startup_mute is
    generic (
        CLOCK_KHZ : positive := 20000;
        MUTE_MS   : natural := 10000
    );
    port (
        clk, rstn, bypass : in std_logic;
        muted : out std_logic;
        speaker_on : in std_logic := '0'
    );
end entity;

architecture rtl of startup_mute is
    signal tick : natural range 0 to CLOCK_KHZ - 1;
    signal elapsed_ms : natural range 0 to MUTE_MS;
    signal finished : std_logic;
begin
    process(clk, rstn)
    begin
        if rstn = '0' then
            tick <= 0;
            elapsed_ms <= 0;
            finished <= '0';
        elsif rising_edge(clk) then
            if elapsed_ms < MUTE_MS then
                if tick = CLOCK_KHZ - 1 then
                    tick <= 0;
                    elapsed_ms <= elapsed_ms + 1;
                else
                    tick <= tick + 1;
                end if;
            end if;
            if speaker_on = '0' and
               (elapsed_ms = MUTE_MS or
                (MUTE_MS > 0 and elapsed_ms = MUTE_MS - 1 and tick = CLOCK_KHZ - 1)) then
                finished <= '1';
            end if;
        end if;
    end process;

    muted <= '1' when MUTE_MS /= 0 and finished = '0' and bypass = '0' else '0';
end architecture;
