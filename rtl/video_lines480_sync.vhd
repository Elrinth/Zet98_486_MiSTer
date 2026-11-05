-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;

-- The text GDC's 480-line bit (SYNC active lines above 400) changes only
-- when software reprograms the display. Resolve that single CPU-clock bit in
-- the video clock before CRTC98 stages it and latches it at frame start.
entity video_lines480_sync is
    port(video_clk, video_rstn, cpu_lines480 : in std_logic;
         lines480 : out std_logic);
end;
architecture rtl of video_lines480_sync is
    signal lines480_sync : std_logic_vector(1 downto 0);
    attribute preserve : boolean;
    attribute preserve of lines480_sync : signal is true;
    attribute altera_attribute : string;
    attribute altera_attribute of lines480_sync : signal is
        "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
begin
    process(video_clk, video_rstn) begin
        if video_rstn='0' then lines480_sync<="00";
        elsif rising_edge(video_clk) then lines480_sync<=lines480_sync(0) & cpu_lines480;
        end if;
    end process;
    lines480 <= lines480_sync(1);
end;
