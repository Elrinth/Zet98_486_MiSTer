-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity dma_byte_pointer_tb is end;
architecture test of dma_byte_pointer_tb is
    signal clk : std_logic := '0';
    signal rstn, pcs, prd, pwr : std_logic := '0';
    signal addr : std_logic_vector(3 downto 0) := (others=>'0');
    signal din, dout : std_logic_vector(7 downto 0) := (others=>'0');
    signal drq, dack : std_logic_vector(3 downto 0) := (others=>'0');
    signal busreq : std_logic;
begin
    clk <= not clk after 5 ns;
    dut: entity work.DMA8237 port map(
        PCS=>pcs, PADDR=>addr, PRD=>prd, PWR=>pwr, PRDATA=>dout, PWDATA=>din,
        PDOE=>open, INT=>open, DREQ=>drq, DACK=>dack, BUSREQ=>busreq,
        BUSACK=>'0', DADDR=>open, DAOE=>open, MEMRD=>open, MEMWR=>open,
        IORD=>open, IOWR=>open, IOWAIT=>'0', IOACK=>'0', MEMACK=>'0',
        TC=>open, ACARRY=>open, CURCH=>open, clk=>clk, rstn=>rstn);
    process
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure wr(regnum, value: natural) is begin
            addr<=std_logic_vector(to_unsigned(regnum,4));
            din<=std_logic_vector(to_unsigned(value,8)); pcs<='1'; pwr<='1';
            tick; tick; pwr<='0'; tick; tick; pcs<='0'; tick;
        end;
        procedure rd(regnum, expected: natural) is begin
            addr<=std_logic_vector(to_unsigned(regnum,4)); pcs<='1'; prd<='1';
            tick;
            assert dout=std_logic_vector(to_unsigned(expected,8))
                report "DMA byte pointer wrong at register " & integer'image(regnum) &
                       ": expected " & integer'image(expected) &
                       " got " & integer'image(to_integer(unsigned(dout))) severity failure;
            prd<='0'; tick; tick; pcs<='0'; tick;
        end;
    begin
        tick; tick; rstn<='1'; tick;
        wr(8,16#40#); -- normal command, active-high DACK; controller enabled
        for ch in 0 to 3 loop
            wr(ch*2,16#34#+ch); wr(ch*2,16#12#+ch);
            wr(ch*2+1,16#78#+ch); wr(ch*2+1,16#56#+ch);
            rd(ch*2,16#34#+ch); -- leave each channel's pointer at high byte
        end loop;
        wr(12,16#5a#); -- port 19h, any data clears all byte pointers
        for ch in 0 to 3 loop
            rd(ch*2,16#34#+ch); rd(ch*2,16#12#+ch);
            rd(ch*2+1,16#78#+ch); rd(ch*2+1,16#56#+ch);
        end loop;
        -- An odd count read must also be undone before fresh programming.
        rd(5,16#7a#);
        wr(12,0);
        wr(4,16#ab#); wr(4,16#cd#); wr(5,16#ef#); wr(5,16#01#);
        rd(4,16#ab#); rd(4,16#cd#); rd(5,16#ef#); rd(5,16#01#);
        assert dack="0000" report "Byte clear changed DACK polarity/command" severity failure;
        wr(10,2); -- unmask channel 2
        wr(12,255); drq(2)<='1';
        for i in 1 to 8 loop tick; end loop;
        assert busreq='1' report "Byte clear masked/disabled a DMA channel" severity failure;
        report "PASS: DMA port 19h clears all byte pointers after odd reads, preserves registers and command/mask";
        stop; wait;
    end process;
end;
