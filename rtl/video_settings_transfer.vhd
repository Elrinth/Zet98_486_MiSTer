-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;

-- Continuously refresh a coherent snapshot of slowly programmed settings.
-- The source stays held until the receiving domain acknowledges its copy.
entity video_settings_transfer is
    generic(WIDTH:positive:=121);
    port(cpu_clk,video_clk,rstn:in std_logic;
         settings_in:in std_logic_vector(WIDTH-1 downto 0);
         settings_out:out std_logic_vector(WIDTH-1 downto 0));
end;
architecture rtl of video_settings_transfer is
    signal held_data,transfer_data,received_data:std_logic_vector(WIDTH-1 downto 0);
    signal request_toggle,ack_toggle,cpu_rstn,video_rstn:std_logic;
    signal request_sync,ack_sync:std_logic_vector(1 downto 0);
    attribute preserve:boolean;
    attribute preserve of held_data,request_sync,ack_sync:signal is true;
    attribute altera_attribute:string;
    attribute altera_attribute of request_sync,ack_sync:signal is
        "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
begin
    settings_cpu_reset:entity work.reset_release port map(cpu_clk,rstn,cpu_rstn);
    settings_video_reset:entity work.reset_release port map(video_clk,rstn,video_rstn);
    transfer_data<=held_data;
    settings_out<=received_data;
    process(cpu_clk,cpu_rstn) begin
        if cpu_rstn='0' then
            held_data<=(others=>'0');request_toggle<='0';ack_sync<="00";
        elsif rising_edge(cpu_clk) then
            ack_sync<=ack_sync(0) & ack_toggle;
            if ack_sync(1)=request_toggle then
                held_data<=settings_in;
                request_toggle<=not request_toggle;
            end if;
        end if;
    end process;
    process(video_clk,video_rstn) begin
        if video_rstn='0' then
            received_data<=(others=>'0');ack_toggle<='0';request_sync<="00";
        elsif rising_edge(video_clk) then
            request_sync<=request_sync(0) & request_toggle;
            if request_sync(1)/=ack_toggle then
                -- synthesis translate_off
                -- Delay-injection tests exercise this bundled-data contract.
                assert transfer_data=held_data report "settings payload not settled" severity failure;
                -- synthesis translate_on
                received_data<=transfer_data;
                ack_toggle<=request_sync(1);
            end if;
        end if;
    end process;
end;
