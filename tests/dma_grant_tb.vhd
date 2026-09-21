-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity dma_grant_tb is end;
architecture test of dma_grant_tb is
    signal clk : std_logic := '0';
    signal rstn, cpustb, dmabreq : std_logic := '0';
    signal dmaen : std_logic;
begin
    clk <= not clk after 5 ns;
    dut: entity work.DMASW port map(cpustb,dmabreq,dmaen,clk,rstn);
    process
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
    begin
        tick; assert dmaen='0' severity failure;
        rstn<='1'; tick;
        -- No preceding CPU transaction: the cached/HLT case.
        dmabreq<='1'; tick;
        assert dmaen='1' report "DMA request stalled on an idle CPU bus" severity failure;
        cpustb<='1'; tick;
        assert dmaen='1' report "Waiting CPU preempted DMA ownership" severity failure;
        dmabreq<='0'; tick;
        assert dmaen='0' report "DMA failed to release" severity failure;
        -- An in-flight CPU transfer must finish before a grant.
        dmabreq<='1';
        for i in 1 to 8 loop tick; assert dmaen='0' severity failure; end loop;
        cpustb<='0'; tick;
        assert dmaen='1' report "DMA failed to acquire after CPU completion" severity failure;
        rstn<='0'; wait for 1 ns;
        assert dmaen='0' report "Reset did not release DMA" severity failure;
        report "PASS: DMA grants idle/cached/HLT bus, waits for CPU completion, retains ownership, releases/reset";
        stop;
        wait;
    end process;
end;
