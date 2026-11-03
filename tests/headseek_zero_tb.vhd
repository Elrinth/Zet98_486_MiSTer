-- SPDX-License-Identifier: GPL-3.0-or-later
-- headseek4: a SEEK to the cylinder the head is already on must end on a
-- seek tick, not in the cycle after the command (a uPD765 compares NCN with
-- PCN on its step timing). Star Cruiser's own floppy driver stores its
-- "wait for the seek" state right after the last SEEK byte; the same-cycle
-- interrupt cleared that state before it was stored and the game hung.
-- Normal seeks must still step to their cylinder.
library ieee;
use ieee.std_logic_1164.all;

entity headseek_zero_tb is
end headseek_zero_tb;

architecture tb of headseek_zero_tb is
	signal clk		:std_logic := '0';
	signal rstn		:std_logic := '0';
	signal dest0	:integer range 0 to 79 := 0;
	signal destset	:std_logic_vector(3 downto 0) := "0000";
	signal reach	:std_logic_vector(3 downto 0);
	signal busy		:std_logic_vector(3 downto 0);
	signal serr		:std_logic_vector(3 downto 0);
	signal cur0, cur1, cur2, cur3 :integer range 0 to 79;
	signal sft		:std_logic := '0';
	signal track0	:std_logic;
	signal step		:std_logic;
	signal sdir		:std_logic;
	signal cyc		:integer := 0;
begin
	clk <= not clk after 5 ns;
	-- a seek tick every 500 cycles
	process(clk) begin
		if rising_edge(clk) then
			cyc <= cyc + 1;
			if cyc mod 500 = 499 then sft <= '1'; else sft <= '0'; end if;
		end if;
	end process;
	track0 <= '1' when cur0 = 0 else '0';

	dut: entity work.headseek4 generic map(79, 30) port map(
		dest0=>dest0, dest1=>0, dest2=>0, dest3=>0, destset=>destset, init=>"0000",
		setwait=>30, usel=>"00", cur0=>cur0, cur1=>cur1, cur2=>cur2, cur3=>cur3,
		reachtrack=>reach, busy=>busy, seekerr=>serr, track0=>track0, seek=>step, sdir=>sdir,
		sft=>sft, clk=>clk, rstn=>rstn);

	stim: process
		procedure do_seek(c :integer; zero :boolean) is
			variable n :integer := 0;
		begin
			dest0 <= c;
			-- start just after a tick, so the next one is 500 cycles away
			wait until rising_edge(clk) and sft = '1';
			destset <= "0001";
			wait until rising_edge(clk);
			destset <= "0000";
			loop
				wait until rising_edge(clk);
				n := n + 1;
				exit when reach(0) = '1';
				assert n < 200000 report "seek to " & integer'image(c) & ": no end" severity failure;
			end loop;
			report "seek to " & integer'image(c) & " ended after " & integer'image(n) & " cycles";
			if zero then
				assert n > 100 report "seek to the current cylinder ended after " & integer'image(n) &
					" cycles (same-cycle interrupt)" severity error;
			end if;
			assert cur0 = c report "head at " & integer'image(cur0) & ", wanted " & integer'image(c) severity error;
			wait for 100 ns;
		end procedure;
	begin
		wait for 50 ns;
		rstn <= '1';
		wait for 50 ns;
		do_seek(0, true);		-- the head is on cylinder 0 after reset
		do_seek(2, false);
		do_seek(2, true);
		report "PASS zero-step seeks end on a seek tick";
		std.env.finish;
	end process;
end tb;
