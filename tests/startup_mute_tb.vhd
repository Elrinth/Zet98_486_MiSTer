library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity startup_mute_tb is end entity;
architecture test of startup_mute_tb is
    signal clk : std_logic := '0';
    signal rstn : std_logic := '0';
    signal bypass : std_logic := '0';
    signal speaker_on : std_logic := '0';
    signal muted, no_mute : std_logic;
begin
    clk <= not clk after 5 ns;
    dut : entity work.startup_mute
        generic map(CLOCK_KHZ => 4, MUTE_MS => 3)
        port map(clk, rstn, bypass, muted, speaker_on);
    zero_interval : entity work.startup_mute
        generic map(CLOCK_KHZ => 1, MUTE_MS => 0)
        port map(clk, rstn, bypass, no_mute);
    process
        procedure cycle is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
            assert no_mute = '0' report "Zero-duration mute suppressed sound" severity failure;
        end procedure;
    begin
        wait for 1 ns;
        assert muted = '1' report "Startup was not muted" severity failure;
        wait until falling_edge(clk);
        rstn <= '1';
        for i in 1 to 12 loop
            cycle;
            if i < 12 then
                assert muted = '1' report "Mute expired early" severity failure;
            else
                assert muted = '0' report "Speaker was not restored on time" severity failure;
            end if;
        end loop;
        for i in 1 to 20 loop
            cycle;
            assert muted = '0' report "Timer wrapped and muted later audio" severity failure;
        end loop;
        wait until falling_edge(clk);
        rstn <= '0';
        wait for 1 ns;
        assert muted = '1' report "Core reset did not rearm startup mute" severity failure;
        wait until falling_edge(clk);
        rstn <= '1';
        bypass <= '1';
        for i in 1 to 6 loop
            cycle;
            assert muted = '0' report "Menu bypass did not enable speaker" severity failure;
        end loop;
        wait until falling_edge(clk);
        bypass <= '0';
        for i in 7 to 12 loop
            cycle;
            if i < 12 then
                assert muted = '1' report "Mute interval was lost while bypassed" severity failure;
            else
                assert muted = '0' report "Bypass restarted the timer" severity failure;
            end if;
        end loop;
        bypass <= '1';
        cycle;
        bypass <= '0';
        cycle;
        assert muted = '0' report "Post-boot menu change muted later audio" severity failure;
        wait until falling_edge(clk);
        rstn <= '0'; speaker_on <= '1';
        wait until falling_edge(clk); rstn <= '1';
        for i in 1 to 40 loop
            cycle;
            assert muted = '1' report "Timer exposed the tail of a long boot beep" severity failure;
        end loop;
        bypass <= '1'; cycle;
        assert muted = '0' report "Bypass did not enable an ongoing boot beep" severity failure;
        bypass <= '0'; cycle;
        assert muted = '1' report "Bypass cancelled the pending startup mute" severity failure;
        speaker_on <= '0'; cycle;
        assert muted = '0' report "Speaker did not restore after the boot beep ended" severity failure;
        speaker_on <= '1';
        for i in 1 to 40 loop
            cycle;
            assert muted = '0' report "A later software speaker tone was muted" severity failure;
        end loop;
        report "PASS: startup mute duration, long-beep suppression, later tones, reset, bypass, and saturation" severity note;
        finish;
    end process;
end architecture;
