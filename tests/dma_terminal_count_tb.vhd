-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity dma_terminal_count_tb is end;
architecture test of dma_terminal_count_tb is
    signal clk : std_logic := '0';
    signal rstn, prd, pwr, addr, auto_init, decrement, drq : std_logic := '0';
    signal din, dout : std_logic_vector(7 downto 0) := (others=>'0');
    signal busreq, memrd, memwr, tc : std_logic;
    signal tc_count : natural := 0;
begin
    clk <= not clk after 5 ns;
    dut: entity work.DMA1ch port map(
        PADDR=>addr, PRD=>prd, PWR=>pwr, PRDATA=>dout, PWDATA=>din, PDOE=>open,
        CONTEN=>'1', CHEN=>'1', DIRMODE=>"01", AUTOINI=>auto_init,
        DEC_INCn=>decrement, OPMODE=>"01", DREQ=>drq,
        BUSREQ=>busreq, BUSACK=>busreq, DACK=>open, DADDR=>open, DAOE=>open,
        MEMRD=>memrd, MEMWR=>memwr, IORD=>open, IOWR=>open,
        IOWAIT=>'0', IOACK=>'0', MEMACK=>memwr, TC=>tc, ACARRY=>open,
        clk=>clk, rstn=>rstn);
    process(clk) begin
        if rising_edge(clk) and tc='1' then tc_count <= tc_count+1; end if;
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
            assert value=expected report "DMA terminal register " & integer'image(regnum) &
                " expected " & integer'image(expected) & " got " & integer'image(value)
                severity failure;
        end;
        variable pulses : natural;
    begin
        for autoini in 0 to 1 loop
            for down in 0 to 1 loop
                rstn<='0'; tick; tick; rstn<='1'; tick;
                if autoini=0 then auto_init<='0'; else auto_init<='1'; end if;
                if down=0 then decrement<='0'; else decrement<='1'; end if;
                wr(0,16#34#); wr(0,16#12#); -- address 1234h
                wr(1,2); wr(1,0); -- three bytes
                pulses:=tc_count;
                drq<='1';
                for byte in 1 to 3 loop
                    wait until memwr='1';
                    if byte=3 then drq<='0'; end if;
                    wait until memwr='0';
                end loop;
                for i in 1 to 8 loop tick; end loop;
                assert tc_count=pulses+1 report "Missing or duplicate TC pulse" severity failure;
                if autoini=1 then
                    rd_word(0,16#1234#); rd_word(1,2);
                else
                    if down=0 then rd_word(0,16#1237#); else rd_word(0,16#1231#); end if;
                    rd_word(1,16#ffff#);
                end if;
            end loop;
        end loop;
        report "PASS: non-auto-init TC leaves FFFFh; auto-init reloads count/address; both address directions";
        stop; wait;
    end process;
    process begin
        wait for 100 us;
        assert false report "DMA terminal count test timed out" severity failure;
    end process;
end;
