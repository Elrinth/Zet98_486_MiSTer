-- SPDX-License-Identifier: GPL-3.0-or-later
-- 8237 verify transfers (mode bits 3:2 = 00) move no data: each byte is a
-- device acknowledge (DACK with the device read the FDC needs) and no memory
-- cycle, so nothing answers MEMACK. Windows 95 checks a floppy with a DMA
-- verify READ DATA first; a memory-to-device cycle there made the FDC overrun.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity dma_verify_tb is end;
architecture test of dma_verify_tb is
    signal clk : std_logic := '0';
    signal rstn, prd, pwr, addr, drq : std_logic := '0';
    signal din, dout : std_logic_vector(7 downto 0) := (others=>'0');
    signal busreq, dack, memrd, memwr, iord, iowr, tc : std_logic;
    signal acks, mem_cycles, io_writes, tcs : natural := 0;
begin
    clk <= not clk after 5 ns;
    dut: entity work.DMA1ch port map(
        PADDR=>addr, PRD=>prd, PWR=>pwr, PRDATA=>dout, PWDATA=>din, PDOE=>open,
        CONTEN=>'1', CHEN=>'1', DIRMODE=>"00", AUTOINI=>'0',
        DEC_INCn=>'0', OPMODE=>"01", DREQ=>drq,
        BUSREQ=>busreq, BUSACK=>busreq, DACK=>dack, DADDR=>open, DAOE=>open,
        MEMRD=>memrd, MEMWR=>memwr, IORD=>iord, IOWR=>iowr,
        IOWAIT=>'0', IOACK=>'0', MEMACK=>'0', TC=>tc, ACARRY=>open,
        clk=>clk, rstn=>rstn);
    process(clk)
        variable last : std_logic := '0';
    begin
        if rising_edge(clk) then
            if dack='1' and iord='1' and last='0' then acks <= acks+1; end if;
            last := dack and iord;
            if memrd='1' or memwr='1' then mem_cycles <= mem_cycles+1; end if;
            if iowr='1' then io_writes <= io_writes+1; end if;
            if tc='1' then tcs <= tcs+1; end if;
        end if;
    end process;
    process
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure wr(regnum, value: natural) is begin
            if regnum=0 then addr<='0'; else addr<='1'; end if;
            din<=std_logic_vector(to_unsigned(value,8)); pwr<='1';
            tick; tick; pwr<='0'; tick; tick;
        end;
        procedure rd_word(regnum, expected: natural) is
            variable value : natural := 0;
        begin
            if regnum=0 then addr<='0'; else addr<='1'; end if;
            for byte in 0 to 1 loop
                prd<='1'; tick;
                value:=value+to_integer(unsigned(dout))*256**byte;
                prd<='0'; tick; tick;
            end loop;
            assert value=expected report "register " & integer'image(regnum) &
                " expected " & integer'image(expected) & " got " & integer'image(value)
                severity failure;
        end;
    begin
        rstn<='0'; tick; tick; rstn<='1'; tick;
        wr(0,16#00#); wr(0,16#40#);   -- address 4000h
        wr(1,2); wr(1,0);             -- three bytes
        drq<='1';
        for byte in 1 to 3 loop
            wait until dack='1' and iord='1' for 2 us;
            assert dack='1' report "verify byte " & integer'image(byte) & ": no device acknowledge" severity failure;
            if byte=3 then drq<='0'; end if;
            wait until dack='0' for 2 us;
            assert dack='0' report "verify cycle never ended (waiting for a memory acknowledge?)" severity failure;
        end loop;
        for i in 1 to 10 loop tick; end loop;
        assert acks=3 report "expected 3 device acknowledges, got " & integer'image(acks) severity failure;
        assert mem_cycles=0 report "verify ran a memory cycle" severity failure;
        assert io_writes=0 report "verify wrote to the device" severity failure;
        assert tcs=1 report "expected one TC pulse, got " & integer'image(tcs) severity failure;
        rd_word(0,16#4003#); rd_word(1,16#ffff#);
        report "PASS: verify acknowledges the device per byte, no memory cycle, one TC";
        stop; wait;
    end process;
    process begin
        wait for 100 us;
        assert false report "DMA verify test timed out" severity failure;
    end process;
end;
