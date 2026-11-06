-- usart_tx_tb.vhd : the RS-232C transmitter, an 8251 whose TxC/RxC is PIT channel 2
-- as on the PC-98, sends bytes and returns TxRDY at the programmed baud rate.
-- Yuugiri's HMM MIDI driver (no MPU board: RS-232C) programs channel 2 for mode 3,
-- count 4, resets the 8251 (00 00 00 40h), sets mode 4Eh (x16, 8N1) and command 15h,
-- then polls TxRDY (status bit 0) before every byte. CLOCKED=false ties the clocks
-- off as B279 did: TxRDY never returns after the first byte.
-- Also checks the frames on TXD and the IR4 gating by system port C bits 0-2.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity usart_tx_tb is
generic(CLOCKED : boolean := true);
end entity;

architecture sim of usart_tx_tb is
	constant CLK_PERIOD	: time := 20 ns;					-- 50 MHz
	constant BIT_TIME	: time := 26041 ns;					-- 38400 baud: 2.4576 MHz / 4 / 16
	type bytes is array(natural range <>) of std_logic_vector(7 downto 0);
	constant SENT		: bytes := (x"90", x"3C", x"7F", x"F0", x"55");

	signal clk		: std_logic := '0';
	signal rstn		: std_logic := '0';
	signal sft		: std_logic := '0';
	signal wdat		: std_logic_vector(7 downto 0) := x"00";
	signal pit_cs, pit_wr	: std_logic := '0';
	signal pit_addr	: std_logic_vector(1 downto 0) := "00";
	signal cntout	: std_logic_vector(2 downto 0);
	signal com_csn, com_wrn, com_rdn : std_logic := '1';
	signal com_cd	: std_logic := '1';
	signal com_odat	: std_logic_vector(7 downto 0);
	signal txd, txrdy, txemp, rxrdy, txc : std_logic;
	signal portc	: std_logic_vector(2 downto 0) := "000";	-- 35h bits 0-2: RXRE TXEE TXRE
	signal irq		: std_logic;
	signal received	: bytes(0 to SENT'length - 1) := (others => x"00");
	signal nrx		: natural := 0;
	signal framing	: boolean := false;
begin
	clk <= not clk after CLK_PERIOD / 2;

	-- PIT input clock enable, 2.4576 MHz on average
	process(clk)
		variable acc : integer := 0;
	begin
		if rising_edge(clk) then
			sft <= '0';
			acc := acc + 24576;
			if acc >= 500000 then
				acc := acc - 500000;
				sft <= '1';
			end if;
		end if;
	end process;

	pit: entity work.PTC8253 port map(
		CS => pit_cs, ADDR => pit_addr, RD => '0', WR => pit_wr, RDAT => open, WDAT => wdat, DOE => open,
		CNTIN => sft & sft & sft, TRIG => "111", CNTOUT => cntout, clk => clk, rstn => rstn);

	txc <= cntout(2) when CLOCKED else '1';

	com: entity work.e8251 port map(
		WRn => com_wrn, RDn => com_rdn, C_Dn => com_cd, CSn => com_csn,
		DATIN => wdat, DATOUT => com_odat, DATOE => open, INTn => open,
		TXD => txd, RxD => '1', DSRn => '1', DTRn => open, RTSn => open, CTSn => '0',
		TxRDY => txrdy, TxEMP => txemp, RxRDY => rxrdy, TxCn => txc, RxCn => txc,
		clk => clk, rstn => rstn);

	-- Zet98MiSTer.vhd's IR4
	irq <= (rxrdy and portc(0)) or (txemp and portc(1)) or (txrdy and portc(2));

	-- TXD receiver: start bit, 8 data bits LSB first, stop bit
	process
		variable b : std_logic_vector(7 downto 0);
	begin
		wait until rstn = '1';
		loop
			wait until falling_edge(txd);
			wait for BIT_TIME / 2;
			if txd /= '0' then framing <= true; end if;
			for i in 0 to 7 loop
				wait for BIT_TIME;
				b(i) := txd;
			end loop;
			wait for BIT_TIME;
			if txd /= '1' then framing <= true; end if;
			if nrx < SENT'length then
				received(nrx) <= b;
			end if;
			nrx <= nrx + 1;
		end loop;
	end process;

	process
		procedure clocks(n : natural) is
		begin
			for i in 1 to n loop
				wait until rising_edge(clk);
			end loop;
		end procedure;

		procedure pit_out(a : std_logic_vector(1 downto 0); d : std_logic_vector(7 downto 0)) is
		begin
			pit_addr <= a; wdat <= d; pit_cs <= '1'; pit_wr <= '1';
			clocks(4);
			pit_wr <= '0'; clocks(1); pit_cs <= '0'; clocks(2);
		end procedure;

		procedure com_out(cd : std_logic; d : std_logic_vector(7 downto 0)) is
		begin
			com_cd <= cd; wdat <= d; com_csn <= '0'; com_wrn <= '0';
			clocks(4);
			com_wrn <= '1'; clocks(1); com_csn <= '1'; clocks(2);
		end procedure;

		procedure status(s : out std_logic_vector(7 downto 0)) is
		begin
			com_cd <= '1'; com_csn <= '0'; com_rdn <= '0';
			clocks(3);
			s := com_odat;
			com_rdn <= '1'; clocks(1); com_csn <= '1'; clocks(2);
		end procedure;

		variable s : std_logic_vector(7 downto 0);
		variable t0, ready_at, last_ready : time;
		variable irq_seen : boolean;
	begin
		clocks(10);
		rstn <= '1';
		clocks(10);
		pit_out("11", x"B6");							-- 77h: channel 2, LSB+MSB, mode 3
		pit_out("10", x"04");							-- 75h: count 4
		pit_out("10", x"00");
		for i in 1 to 3 loop
			com_out('1', x"00");
		end loop;
		com_out('1', x"40");							-- internal reset
		com_out('1', x"4E");							-- async x16, 8 bits, no parity, 1 stop
		com_out('1', x"15");							-- TxEN, RxEN, error reset
		status(s);
		assert s(0) = '1' and s(2) = '1' report "8251 not ready after its setup" severity error;

		-- HMM's send loop: wait for TxRDY, write the byte. Interrupts masked (35h bits 0-2 clear).
		last_ready := now;
		irq_seen := false;
		for i in SENT'range loop
			t0 := now;
			loop
				status(s);
				exit when s(0) = '1';
				if irq = '1' then irq_seen := true; end if;
				assert now - t0 < 2 ms report "TxRDY did not return (byte " & integer'image(i) & ")" severity failure;
			end loop;
			ready_at := now;
			if i >= 2 then									-- back to back: one frame per byte
				assert ready_at - last_ready > 8 * BIT_TIME and ready_at - last_ready < 12 * BIT_TIME
					report "TxRDY interval " & time'image(ready_at - last_ready) & " is not one 10-bit frame" severity error;
			end if;
			last_ready := ready_at;
			com_out('0', SENT(i));
		end loop;
		assert not irq_seen report "IR4 with the RS-232C interrupts masked" severity error;

		-- TXRE: TxRDY is IR4 while the buffer is empty
		loop
			status(s);
			exit when s(0) = '1';
		end loop;
		portc <= "100";
		clocks(2);
		assert irq = '1' report "TXRE: no IR4 with the transmit buffer empty" severity error;
		com_out('0', x"A5");							-- waits behind the frame being sent
		clocks(1);
		assert irq = '0' report "TXRE: IR4 still high with a byte in the buffer" severity error;
		wait until irq = '1' for 30 * BIT_TIME;
		assert irq = '1' report "TXRE: IR4 did not return after the byte moved on" severity error;

		-- TXEE: TxEMPTY is IR4 once the last frame has left
		portc <= "010";
		clocks(2);
		assert irq = '0' report "TXEE: IR4 while still transmitting" severity error;
		wait until irq = '1' for 30 * BIT_TIME;
		assert irq = '1' and txemp = '1' report "TXEE: no IR4 after the last frame" severity error;

		-- RXRE: nothing arrives on an idle line
		portc <= "001";
		wait for 3 * BIT_TIME;
		assert irq = '0' report "RXRE: IR4 with an idle receive line" severity error;

		wait for 2 * BIT_TIME;
		assert nrx = SENT'length + 1 report "TXD carried " & integer'image(nrx) & " frames" severity error;
		assert not framing report "TXD frame without start or stop bit" severity error;
		for i in SENT'range loop
			assert received(i) = SENT(i) report "TXD byte " & integer'image(i) & " wrong" severity error;
		end loop;
		report "usart_tx_tb done" severity note;
		std.env.stop;
		wait;
	end process;
end architecture;
