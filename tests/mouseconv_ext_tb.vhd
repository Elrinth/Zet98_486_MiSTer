-- SPDX-License-Identifier: GPL-3.0-or-later
-- MOUSECONV extra movement/buttons (analog-stick mouse): drive EXTDX/EXTDY
-- strobes, latch through HC like the PC-98 mouse port, read X/Y nibbles.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mouseconv_ext_tb is
end entity;

architecture sim of mouseconv_ext_tb is
	signal clk : std_logic := '0';
	signal rstn : std_logic := '0';
	signal HC, SXY, SHL : std_logic := '0';
	signal MOUSDAT : std_logic_vector(7 downto 0);
	signal MCLKOUT, MDATOUT : std_logic;
	signal EXTDX, EXTDY : std_logic_vector(7 downto 0) := (others=>'0');
	signal EXTSTB : std_logic := '0';
	signal EXTBTN : std_logic_vector(1 downto 0) := "00";
	signal done : boolean := false;
begin
	clk <= not clk after 5 ns when not done else '0';
	dut: entity work.MOUSECONV generic map(CLKCYC=>1000, SFTCYC=>400) port map(
		HC=>HC, SXY=>SXY, SHL=>SHL, MOUSDAT=>MOUSDAT,
		MCLKIN=>'1', MCLKOUT=>MCLKOUT, MDATIN=>'1', MDATOUT=>MDATOUT,
		EXTDX=>EXTDX, EXTDY=>EXTDY, EXTSTB=>EXTSTB, EXTBTN=>EXTBTN,
		clk=>clk, rstn=>rstn);

	process
		procedure tick(n : natural) is
		begin
			for i in 1 to n loop wait until rising_edge(clk); end loop;
		end procedure;
		procedure push(dx, dy : integer) is
		begin
			EXTDX <= std_logic_vector(to_signed(dx, 8));
			EXTDY <= std_logic_vector(to_signed(dy, 8));
			EXTSTB <= '1'; tick(1); EXTSTB <= '0'; tick(3);
		end procedure;
		-- Latch the counters (HC rising) and read both bytes as the BIOS does.
		procedure readxy(x, y : out integer) is
			variable b : std_logic_vector(7 downto 0);
		begin
			HC <= '0'; tick(2); HC <= '1'; tick(2);
			SXY <= '0'; SHL <= '0'; tick(1); b(3 downto 0) := MOUSDAT(3 downto 0);
			SHL <= '1'; tick(1); b(7 downto 4) := MOUSDAT(3 downto 0);
			x := to_integer(signed(b));
			SXY <= '1'; SHL <= '0'; tick(1); b(3 downto 0) := MOUSDAT(3 downto 0);
			SHL <= '1'; tick(1); b(7 downto 4) := MOUSDAT(3 downto 0);
			y := to_integer(signed(b));
			HC <= '0'; tick(2);
		end procedure;
		procedure expect(x, y, wx, wy : integer; what : string) is
		begin
			assert x = wx and y = wy report "FAIL " & what & ": x=" & integer'image(x) &
				" (want " & integer'image(wx) & ") y=" & integer'image(y) &
				" (want " & integer'image(wy) & ")" severity failure;
		end procedure;
		variable x, y : integer;
	begin
		tick(5); rstn <= '1'; tick(20);
		readxy(x, y); expect(x, y, 0, 0, "idle");
		-- +X right; PS/2 +Y up becomes a negative PC-98 Y count. Counts are /4.
		push(40, 20); readxy(x, y); expect(x, y, 10, -5, "one delta");
		readxy(x, y); expect(x, y, 0, 0, "latch clears");
		push(8, -8); push(8, -8); readxy(x, y); expect(x, y, 4, 4, "accumulate");
		for i in 1 to 5 loop push(127, 127); end loop;
		readxy(x, y); expect(x, y, 64, -65, "saturate like PS/2");
		for i in 1 to 5 loop push(-127, -127); end loop;
		readxy(x, y); expect(x, y, -65, 64, "saturate negative");
		assert MOUSDAT(7) = '1' and MOUSDAT(5) = '1' report "FAIL buttons idle" severity failure;
		EXTBTN <= "01"; tick(2);
		assert MOUSDAT(7) = '0' and MOUSDAT(5) = '1' report "FAIL left button" severity failure;
		EXTBTN <= "10"; tick(2);
		assert MOUSDAT(7) = '1' and MOUSDAT(5) = '0' report "FAIL right button" severity failure;
		EXTBTN <= "00"; tick(2);
		report "PASS: MOUSECONV stick input: direction, /4 scaling, latch, accumulation, saturation, buttons";
		done <= true; wait;
	end process;
end architecture;
