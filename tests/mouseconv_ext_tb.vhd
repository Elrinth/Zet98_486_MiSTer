-- SPDX-License-Identifier: GPL-3.0-or-later
-- MOUSECONV extra movement/buttons (analog-stick mouse): drive EXTDX/EXTDY
-- strobes, latch through HC like the PC-98 mouse port, read X/Y nibbles.
-- Then the USB mouse: hps_io ps2_mouse packets through the real PS2DIRECT,
-- after the converter's FF/F6/F4 initialisation.
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
	signal MPKT : std_logic_vector(24 downto 0) := (others=>'0');
	signal EXTDX, EXTDY : std_logic_vector(7 downto 0) := (others=>'0');
	signal EXTSTB : std_logic := '0';
	signal EXTBTN : std_logic_vector(1 downto 0) := "00";
	signal done : boolean := false;
begin
	clk <= not clk after 5 ns when not done else '0';
	dut: entity work.MOUSECONV generic map(CLKCYC=>1000, SFTCYC=>400) port map(
		HC=>HC, SXY=>SXY, SHL=>SHL, MOUSDAT=>MOUSDAT,
		MPKT=>MPKT,
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
		-- One hps_io ps2_mouse event: PS/2 flags (bit 3 set, X/Y signs), X, Y.
		procedure packet(dx, dy : integer; buttons : std_logic_vector(2 downto 0)) is
			variable f : std_logic_vector(7 downto 0);
		begin
			f := "00001" & buttons;
			if dx < 0 then f(4) := '1'; end if;
			if dy < 0 then f(5) := '1'; end if;
			MPKT <= not MPKT(24) & std_logic_vector(to_signed(dy, 8)) &
			        std_logic_vector(to_signed(dx, 8)) & f;
			tick(40);
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
		tick(200000);
		packet(40, 20, "000"); readxy(x, y); expect(x, y, 10, -5, "USB mouse packet");
		packet(-8, 8, "000"); packet(-8, 8, "000"); readxy(x, y); expect(x, y, -4, -4, "USB mouse accumulate");
		for i in 1 to 5 loop packet(127, -127, "000"); end loop;
		readxy(x, y); expect(x, y, 64, 64, "USB mouse saturate");
		packet(0, 0, "001"); tick(4);
		assert MOUSDAT(7) = '0' and MOUSDAT(5) = '1' report "FAIL USB left button" severity failure;
		packet(0, 0, "010"); tick(4);
		assert MOUSDAT(7) = '1' and MOUSDAT(5) = '0' report "FAIL USB right button" severity failure;
		packet(0, 0, "000"); tick(4);
		assert MOUSDAT(7) = '1' and MOUSDAT(5) = '1' report "FAIL USB buttons released" severity failure;
		readxy(x, y);
		-- Stick and USB mouse add up.
		packet(20, 0, "000"); push(20, 0); readxy(x, y); expect(x, y, 10, 0, "stick + USB mouse");
		-- Slow motion: sub-count deltas carry across polls instead of being lost,
		-- and opposite single steps cancel (no floor bias towards left/up).
		readxy(x, y);
		for i in 1 to 3 loop packet(1, -1, "000"); readxy(x, y); expect(x, y, 0, 0, "slow sub-count"); end loop;
		packet(1, -1, "000"); readxy(x, y); expect(x, y, 1, 1, "slow motion carried");
		packet(-1, 1, "000"); packet(1, -1, "000"); readxy(x, y); expect(x, y, 0, 0, "opposite steps cancel");
		report "PASS: USB mouse packets: init gate, direction, /4 scaling, accumulation, saturation, buttons, slow motion";
		report "PASS: MOUSECONV stick input: direction, /4 scaling, latch, accumulation, saturation, buttons";
		done <= true; wait;
	end process;
end architecture;
