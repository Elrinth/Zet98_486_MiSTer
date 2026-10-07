library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity floppy_events_tb is end;
architecture test of floppy_events_tb is
    signal clk : std_logic := '0';
    signal rstn, native_irq, busy, rd, wr, oe, irq : std_logic := '0';
    signal present : std_logic_vector(1 downto 0) := "00";
    signal address : std_logic_vector(15 downto 0) := x"7ED0";
    signal wd, data : std_logic_vector(7 downto 0) := x"00";
begin
    clk <= not clk after 5 ns;
    dut: entity work.pc98_floppy_events port map(clk,rstn,present,native_irq,
        busy,address,rd,wr,wd,data,oe,irq);
    process
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure write_byte(v : std_logic_vector(7 downto 0)) is
        begin wd<=v;wr<='1';tick;wr<='0';tick;end;
    begin
        tick;rstn<='1';tick;present<="11";tick;tick;
        assert irq='0' and data=x"A0" report "legacy BIOS must see no IRQ" severity failure;
        rd<='1';tick;assert oe='1' severity failure;
        address<=x"7ED2";tick;assert oe='0' severity failure;address<=x"7ED0";
        write_byte(x"A5");assert data=x"A8" and irq='0' severity failure;
        busy<='1';present<="10";tick;
        assert data(1 downto 0)="01" and irq='0' report "change lost during transfer" severity failure;
        present<="11";tick;busy<='0';native_irq<='1';tick;
        assert irq='0' and data(2)='1' report "native completion priority" severity failure;
        native_irq<='0';wait for 1 ns;
        assert irq='0' report "missing low interval for edge-triggered PIC" severity failure;
        tick;assert irq='1' report "deferred media IRQ missing" severity failure;
        write_byte(x"81");assert irq='0' and data(1 downto 0)="00" severity failure;
        present<="00";tick;assert data(1 downto 0)="11" severity failure;
        wd<=x"81";wr<='1';tick;
        assert irq='0' report "ack did not re-arm pending IRQ edge" severity failure;
        wr<='0';tick;
        assert data(1 downto 0)="10" and irq='1' report "ack cleared other drive" severity failure;
        -- New transition on the acknowledgement edge must survive.
        present<="10";wd<=x"82";wr<='1';tick;
        assert data(1)='1' report "ack lost simultaneous change" severity failure;
        wr<='0';tick;write_byte(x"82");assert irq='0' severity failure;
        write_byte(x"00");present<="11";tick;tick;
        assert irq='0' and data=x"A0" severity failure;
        write_byte(x"A5");present<="00";tick;assert irq='1' severity failure;
        rstn<='0';tick;assert irq='0' and data=x"A0" report "reset did not disable extension" severity failure;
        report "PASS floppy events: legacy, swap, busy, native IRQ, per-drive ack, race, reset";
        stop;
    end process;
end;
