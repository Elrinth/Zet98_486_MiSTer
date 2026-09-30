-- SPDX-License-Identifier: GPL-3.0-or-later
-- Graphics display page (port A4h) as scanned out. A new page normally takes
-- effect when vertical retrace ends, so a flip made mid-frame does not split
-- the picture (Flame Zapper Kotsujin). But when the drawing page (A6h) is the
-- page still on screen while a flip is pending, the game is about to redraw
-- what is being shown: the flip then applies at once, as on the real machine.
-- Touhou 5 flips mid-frame when a frame runs late and immediately clears the
-- old page; holding that page for the rest of the frame made sprites flicker.
library ieee;
use ieee.std_logic_1164.all;

entity pc98_display_page is
port(
	clk		:in std_logic;
	rstn	:in std_logic;
	vrtc	:in std_logic;		-- vertical retrace
	disp	:in std_logic;		-- display page register (A4h)
	draw	:in std_logic;		-- drawing page register (A6h)
	page	:out std_logic		-- page being scanned out
);
end pc98_display_page;

architecture rtl of pc98_display_page is
signal	shown, vrtc_d	:std_logic;
begin
	process(clk,rstn)begin
		if(rstn='0')then
			shown<='0'; vrtc_d<='0';
		elsif(clk' event and clk='1')then
			vrtc_d<=vrtc;
			if(vrtc_d='1' and vrtc='0')then
				shown<=disp;
			elsif(disp/=shown and draw=shown)then
				shown<=disp;
			end if;
		end if;
	end process;
	page<=shown;
end rtl;
