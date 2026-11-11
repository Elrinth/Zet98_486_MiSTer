-- SPDX-License-Identifier: GPL-3.0-or-later
-- VSYNC interrupt (pc98_vsync_irq) through the master 8259, wired as in
-- Zet98MiSTer.vhd. Yesterday (1990) armed IRQ2 earlier, then runs
-- "cli / unmask IRQ2 / out 64h / popf" before it sets its INT 0Ah vector:
-- a retrace that came while IRQ2 was masked must not fire at the unmask
-- (NP2kai withdraws it when the retrace ends); the next retrace must.
library ieee;
use ieee.std_logic_1164.all;

entity vsync_pic_tb is
    generic (RETRACT :std_logic_vector(7 downto 0) := x"44");
end;
architecture test of vsync_pic_tb is
    signal clk :std_logic := '0';
    signal rstn :std_logic := '0';
    signal mcs, addr, wr, inta, arm, vrtc, vsint :std_logic := '0';
    signal din, mdout :std_logic_vector(7 downto 0) := x"00";
    signal mint, mdoe :std_logic;
    signal ack :std_logic_vector(7 downto 0);
begin
    clk <= not clk after 5 ns;
    vs: entity work.pc98_vsync_irq port map(clk=>clk, rstn=>rstn, arm=>arm, vrtc=>vrtc, ack=>ack(2), irq=>vsint);
    master: entity work.z8259 generic map(RETRACTABLE_IRQS=>RETRACT, LEVEL_IRQS=>x"01") port map(
        CS=>mcs, ADDR=>addr, DIN=>din, DOUT=>mdout, DOE=>mdoe, RD=>'0', WR=>wr,
        IR0=>'0', IR1=>'0', IR2=>vsint, IR3=>'0', IR4=>'0', IR5=>'0', IR6=>'0', IR7=>'0',
        INT=>mint, INTA=>inta, ACK=>ack, CASI=>"000", CASO=>open, CASM=>'1', clk=>clk, rstn=>rstn);
    process
        procedure cycles(n :positive) is begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        procedure write_pic(data_port :std_logic; value :std_logic_vector(7 downto 0)) is begin
            cycles(1); mcs<='1'; addr<=data_port; din<=value; wr<='1';
            cycles(3); wr<='0'; mcs<='0'; cycles(5);
        end;
        procedure write64 is begin
            cycles(1); arm<='1'; cycles(1); arm<='0';
        end;
        procedure retrace is begin
            vrtc<='1'; cycles(12); vrtc<='0'; cycles(30);
        end;
        procedure acknowledge is begin
            inta<='1'; wait for 1 ns;
            assert mdoe='1' and mdout=x"0a" report "IRQ2 not delivered as INT 0Ah" severity failure;
            wait until rising_edge(clk); cycles(1); inta<='0'; cycles(10);
            write_pic('0', x"20");             -- EOI
        end;
    begin
        cycles(3); rstn<='1'; cycles(3);
        write_pic('0', x"11"); write_pic('1', x"08"); write_pic('1', x"80"); write_pic('1', x"0d");
        write_pic('1', x"ff");                 -- everything masked
        -- Armed earlier, retrace while IRQ2 is masked.
        write64; retrace;
        assert mint='0' report "masked IRQ2 delivered" severity failure;
        -- Yesterday's vsync_on: unmask IRQ2 and arm, vector not set yet.
        write_pic('1', x"fb"); write64; cycles(40);
        assert mint='0' report "stale VSYNC request fired when IRQ2 was unmasked" severity failure;
        vrtc<='1'; cycles(4);                  -- the next retrace does interrupt
        assert mint='1' report "no IRQ2 at the retrace after unmasking" severity failure;
        acknowledge; vrtc<='0'; cycles(30); retrace;
        assert mint='0' report "acknowledged IRQ2 repeated without a port 64h write" severity failure;
        -- CLI through a whole retrace: the request is withdrawn when it ends
        -- (an INTA after that gets the default IR7) and raised again next time.
        write64; vrtc<='1'; cycles(4);
        assert mint='1' report "no IRQ2 after arming" severity failure;
        vrtc<='0'; cycles(20);
        assert mint='0' report "unacknowledged IRQ2 still pending after its retrace" severity failure;
        vrtc<='1'; cycles(4);
        assert mint='1' report "unacknowledged IRQ2 not raised at the next retrace" severity failure;
        acknowledge; vrtc<='0'; cycles(30);
        -- Armed while masked and never taken: it keeps being raised, so a game
        -- that unmasks later (without writing 64h again) still gets the next one.
        write_pic('1', x"ff"); write64; retrace; retrace;
        write_pic('1', x"fb"); cycles(40);
        assert mint='0' report "stale VSYNC request fired when IRQ2 was unmasked" severity failure;
        vrtc<='1'; cycles(4);
        assert mint='1' report "armed IRQ2 lost while it was masked" severity failure;
        acknowledge; vrtc<='0'; cycles(30); retrace;
        assert mint='0' report "acknowledged IRQ2 repeated without a port 64h write" severity failure;
        report "PASS: vsync_pic: no stale IRQ2 at unmask, next retrace interrupts, masked arming kept until taken";
        std.env.finish;
    end process;
end;
