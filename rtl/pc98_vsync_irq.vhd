-- SPDX-License-Identifier: GPL-3.0-or-later
-- PC-98 CRT vertical-retrace interrupt (IRQ2). A write to port 64h arms it;
-- the next retrace start raises IRQ2 once, held until the retrace ends (the
-- PIC is edge-triggered). Unarmed retraces raise nothing, as on the PC-98 and
-- in NP2kai (gdc.vsyncint). Games re-arm it from their handler.
library ieee;
use ieee.std_logic_1164.all;

entity pc98_vsync_irq is
port(
	clk		:in std_logic;
	rstn	:in std_logic;
	arm		:in std_logic;		-- write to port 64h
	vrtc	:in std_logic;		-- vertical retrace
	irq		:out std_logic
);
end pc98_vsync_irq;

architecture rtl of pc98_vsync_irq is
signal	armed, active, vrtc_d	:std_logic;
begin
	process(clk,rstn)begin
		if(rstn='0')then
			armed<='0'; active<='0'; vrtc_d<='0';
		elsif(clk' event and clk='1')then
			vrtc_d<=vrtc;
			if(vrtc_d='0' and vrtc='1')then
				active<=armed;
				armed<='0';
			elsif(vrtc='0')then
				active<='0';
			end if;
			if(arm='1')then
				armed<='1';
			end if;
		end if;
	end process;
	irq<=active;
end rtl;
