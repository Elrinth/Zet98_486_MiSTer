-- pc98_vsync_irq: IRQ2 only for the first retrace after a port 64h write.
library ieee;
use ieee.std_logic_1164.all;

entity pc98_vsync_irq_tb is
end pc98_vsync_irq_tb;

architecture sim of pc98_vsync_irq_tb is
	signal clk, rstn, arm, vrtc, irq : std_logic := '0';
	signal done : boolean := false;
	signal pulses : integer := 0;
begin
	clk <= not clk after 5 ns when not done;
	dut : entity work.pc98_vsync_irq port map(clk=>clk, rstn=>rstn, arm=>arm, vrtc=>vrtc, irq=>irq);
	count : process(irq) begin
		if rising_edge(irq) then pulses <= pulses + 1; end if;
	end process;
	stim : process
		procedure wait_clk(n : integer) is begin
			for i in 1 to n loop wait until rising_edge(clk); end loop;
		end procedure;
		procedure frame(arm_in_retrace : boolean := false) is begin
			wait_clk(20);                      -- active display
			vrtc <= '1'; wait_clk(3);
			if arm_in_retrace then arm <= '1'; wait_clk(1); arm <= '0'; end if;
			wait_clk(5); vrtc <= '0'; wait_clk(2);
		end procedure;
		procedure write64 is begin
			wait until falling_edge(clk); arm <= '1'; wait until falling_edge(clk); arm <= '0';
		end procedure;
	begin
		wait_clk(3); rstn <= '1';
		for i in 1 to 3 loop frame; end loop;
		assert pulses = 0 report "IRQ2 without a port 64h write" severity failure;
		write64;
		frame;
		assert pulses = 1 report "no IRQ2 after arming" severity failure;
		assert irq = '0' report "IRQ2 not released after the retrace" severity failure;
		frame; frame;
		assert pulses = 1 report "IRQ2 repeated without re-arming" severity failure;
		frame(arm_in_retrace => true);         -- armed during a retrace: next one
		assert pulses = 1 report "IRQ2 in the retrace that armed it" severity failure;
		frame;
		assert pulses = 2 report "no IRQ2 after arming during a retrace" severity failure;
		write64; rstn <= '0'; wait_clk(2); rstn <= '1';
		frame;
		assert pulses = 2 report "reset did not disarm IRQ2" severity failure;
		report "PASS: pc98_vsync_irq: IRQ2 once per port 64h write, none unarmed, re-arm needed, reset disarms";
		done <= true; wait;
	end process;
end sim;
