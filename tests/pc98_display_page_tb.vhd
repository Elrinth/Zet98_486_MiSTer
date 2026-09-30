-- pc98_display_page: flips wait for retrace end, unless the game draws into
-- the page still on screen (then the pending flip applies at once).
library ieee;
use ieee.std_logic_1164.all;

entity pc98_display_page_tb is
end pc98_display_page_tb;

architecture sim of pc98_display_page_tb is
	signal clk, rstn, vrtc, disp, draw, page : std_logic := '0';
	signal done : boolean := false;
begin
	clk <= not clk after 5 ns when not done;
	dut : entity work.pc98_display_page port map(clk=>clk, rstn=>rstn, vrtc=>vrtc, disp=>disp, draw=>draw, page=>page);
	stim : process
		procedure wait_clk(n : integer) is begin
			for i in 1 to n loop wait until rising_edge(clk); end loop;
		end procedure;
		procedure retrace is begin
			vrtc <= '1'; wait_clk(5); vrtc <= '0'; wait_clk(2);
		end procedure;
	begin
		wait_clk(2); rstn <= '1'; draw <= '1'; wait_clk(2);
		-- flip during retrace (invisible either way): in effect when it ends
		vrtc <= '1'; wait_clk(2); disp <= '1'; draw <= '0'; wait_clk(3);
		vrtc <= '0'; wait_clk(2);
		assert page = '1' report "flip not applied at retrace end" severity failure;
		-- mid-frame flip, still drawing into the hidden page (Flame Zapper):
		-- the old page stays for the rest of the frame
		wait_clk(5); disp <= '0'; wait_clk(10);
		assert page = '1' report "mid-frame flip split the frame" severity failure;
		retrace;
		assert page = '0' report "held flip not applied at the next retrace" severity failure;
		-- mid-frame flip, then drawing into the page still shown (Touhou 5):
		-- the flip applies at once
		draw <= '1'; wait_clk(5); disp <= '1'; wait_clk(3);
		assert page = '0' report "flip applied although the drawing page is hidden" severity failure;
		draw <= '0'; wait_clk(3);
		assert page = '1' report "drawing into the shown page did not apply the pending flip" severity failure;
		-- drawing into the shown page without a pending flip changes nothing
		draw <= '1'; wait_clk(3);
		assert page = '1' report "page changed without a flip" severity failure;
		report "PASS: pc98_display_page: flips at retrace end, mid-frame flips held, applied at once when the shown page is drawn to";
		done <= true; wait;
	end process;
end sim;
