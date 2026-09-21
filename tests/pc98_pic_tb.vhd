-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity pc98_pic_tb is end;
architecture test of pc98_pic_tb is
    signal clk :std_logic := '0';
    signal rstn :std_logic := '0';
    signal mcs, scs, addr, wr, inta :std_logic := '0';
    signal din, mdout, sdout :std_logic_vector(7 downto 0) := x"00";
    signal mirq, sirq :std_logic_vector(7 downto 0) := x"00";
    signal mint, sint, mdoe, sdoe :std_logic;
    signal cascade :std_logic_vector(2 downto 0);
    signal pcm_irq :std_logic := '0';
begin
    clk <= not clk after 5 ns;
    master: entity work.z8259 port map(
        CS=>mcs, ADDR=>addr, DIN=>din, DOUT=>mdout, DOE=>mdoe, RD=>'0', WR=>wr,
        IR0=>mirq(0), IR1=>mirq(1), IR2=>mirq(2), IR3=>mirq(3),
        IR4=>mirq(4), IR5=>mirq(5), IR6=>mirq(6), IR7=>sint,
        INT=>mint, INTA=>inta, CASI=>"000", CASO=>cascade, CASM=>'1', clk=>clk, rstn=>rstn);
    slave: entity work.z8259 port map(
        CS=>scs, ADDR=>addr, DIN=>din, DOUT=>sdout, DOE=>sdoe, RD=>'0', WR=>wr,
        IR0=>sirq(0), IR1=>sirq(1), IR2=>sirq(2), IR3=>sirq(3),
        IR4=>(sirq(4) or pcm_irq), IR5=>sirq(5), IR6=>sirq(6), IR7=>sirq(7),
        INT=>sint, INTA=>inta, CASI=>cascade, CASO=>open, CASM=>'0', clk=>clk, rstn=>rstn);
    process
        procedure cycles(n :positive) is begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        procedure write_pic(is_slave :boolean; data_port :std_logic; value :std_logic_vector(7 downto 0)) is begin
            cycles(1);
            if is_slave then scs<='1'; else mcs<='1'; end if;
            addr<=data_port; din<=value; wr<='1';
            cycles(3); wr<='0'; scs<='0'; mcs<='0'; cycles(5);
        end;
        procedure await_irq is begin
            for i in 1 to 30 loop
                exit when mint='1'; cycles(1);
            end loop;
            assert mint='1' report "missing PIC interrupt" severity failure;
        end;
        procedure acknowledge(is_slave :boolean; vector :std_logic_vector(7 downto 0)) is begin
            inta<='1'; wait for 1 ns;
            if is_slave then
                assert mdoe='0' and sdoe='1' and sdout=vector
                    report "wrong cascaded interrupt vector" severity failure;
            else
                assert mdoe='1' and sdoe='0' and mdout=vector
                    report "wrong master interrupt vector" severity failure;
            end if;
            -- ao486 samples the vector at this edge with interrupt_done high.
            wait until rising_edge(clk); cycles(1); inta<='0'; cycles(10);
            assert mint='0' report "PIC did not enter in-service state" severity failure;
        end;
    begin
        cycles(3); rstn<='1'; cycles(3);
        write_pic(false, '0', x"11"); write_pic(false, '1', x"08");
        write_pic(false, '1', x"80"); write_pic(false, '1', x"0d");
        write_pic(false, '1', x"7d"); -- keyboard and cascade unmasked
        write_pic(true, '0', x"11"); write_pic(true, '1', x"10");
        write_pic(true, '1', x"07"); write_pic(true, '1', x"09");
        write_pic(true, '1', x"ef"); -- slave IRQ4 unmasked
        mirq(1)<='1'; cycles(2); mirq(1)<='0'; await_irq;
        acknowledge(false, x"09"); write_pic(false, '0', x"20"); cycles(12);
        assert mint='0' report "master IRQ repeated after EOI" severity failure;
        sirq(4)<='1'; cycles(2); sirq(4)<='0'; await_irq;
        acknowledge(true, x"14");
        write_pic(true, '0', x"20"); write_pic(false, '0', x"20"); cycles(12);
        assert mint='0' report "slave IRQ repeated after EOI" severity failure;
        mirq(0)<='1'; cycles(2); mirq(0)<='0'; cycles(20);
        assert mint='0' report "masked IRQ delivered" severity failure;
        -- IRQ12 is shared by the FM timer and PCM FIFO. Clearing one source
        -- cannot withdraw the other, and servicing both must leave no repeat.
        sirq(4)<='1'; pcm_irq<='1'; await_irq;
        pcm_irq<='0'; cycles(3);
        assert mint='1' report "clearing PCM withdrew pending FM IRQ" severity failure;
        acknowledge(true,x"14"); sirq(4)<='0';
        write_pic(true,'0',x"20"); write_pic(false,'0',x"20"); cycles(12);
        assert mint='0' report "shared sound IRQ repeated after both cleared" severity failure;
        pcm_irq<='1'; await_irq; acknowledge(true,x"14"); pcm_irq<='0';
        write_pic(true,'0',x"20"); write_pic(false,'0',x"20"); cycles(12);
        assert mint='0' report "PCM-only IRQ repeated after EOI" severity failure;
        -- MPU-PC98II INT2 is master IRQ6 (vector 0Eh), not IBM-PC IRQ9.
        write_pic(false,'1',x"3d");
        for byte_index in 1 to 32 loop
            mirq(6)<='1'; await_irq; acknowledge(false,x"0e"); mirq(6)<='0';
            write_pic(false,'0',x"20"); cycles(12);
            assert mint='0' report "MPU IRQ6 repeated after byte consumption and EOI" severity failure;
        end loop;
        -- MIDI and sound can be pending together: IRQ6 outranks the cascade,
        -- then the FM/PCM interrupt must remain deliverable after its EOI.
        mirq(6)<='1'; sirq(4)<='1'; cycles(12); await_irq;
        acknowledge(false,x"0e"); mirq(6)<='0'; write_pic(false,'0',x"20");
        await_irq; acknowledge(true,x"14"); sirq(4)<='0';
        write_pic(true,'0',x"20"); write_pic(false,'0',x"20"); cycles(12);
        assert mint='0' report "Simultaneous MIDI/sound interrupts did not clear" severity failure;
        report "PASS: 32 MPU IRQ6 vectors/EOIs and simultaneous MIDI + cascaded IRQ12";
        report "PASS: existing PC-98 PICs: master/slave vectors, one-cycle acknowledge, masking and EOI";
        report "PASS: shared IRQ12 retains FM when PCM clears, and delivers subsequent PCM-only vector";
        finish;
    end process;
end;
