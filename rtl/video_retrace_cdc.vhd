-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;

-- Register decoded raster status before crossing to the CPU/PIC/GDC domain.
-- The two bits are independent long-lived levels, not an encoded bus.
-- Video output timing itself is unchanged; software sees <= one source plus
-- two destination periods of latency. No timing paths are excluded here.
entity video_retrace_cdc is
    port (
        video_clk, video_rstn : in std_logic;
        cpu_clk, cpu_rstn : in std_logic;
        vrtc_in, hrtc_in : in std_logic;
        vrtc_out, hrtc_out : out std_logic
    );
end entity;

architecture rtl of video_retrace_cdc is
    signal source_status, status_meta, status_sync : std_logic_vector(1 downto 0);
    attribute preserve : boolean;
    attribute preserve of source_status, status_meta, status_sync : signal is true;
    attribute altera_attribute : string;
    attribute altera_attribute of status_meta, status_sync : signal is
        "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
begin
    process(video_clk, video_rstn) begin
        if video_rstn = '0' then
            source_status <= "00";
        elsif rising_edge(video_clk) then
            source_status <= vrtc_in & hrtc_in;
        end if;
    end process;

    process(cpu_clk, cpu_rstn) begin
        if cpu_rstn = '0' then
            status_meta <= "00";
            status_sync <= "00";
        elsif rising_edge(cpu_clk) then
            status_meta <= source_status;
            status_sync <= status_meta;
        end if;
    end process;
    vrtc_out <= status_sync(1);
    hrtc_out <= status_sync(0);
end architecture;
