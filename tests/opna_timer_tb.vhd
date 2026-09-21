-- SPDX-License-Identifier: GPL-3.0-or-later
-- Exercise the real OPNA register/timer logic. Audio synthesis components are
-- intentionally unbound: this bench checks status/IRQ, not waveform quality.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity opna_timer_tb is
    generic(DIVISOR:positive:=5);
end;
architecture test of opna_timer_tb is
    signal clk:std_logic:='0';
    signal rstn:std_logic:='0';
    signal sft:std_logic;
    signal phase:integer range 0 to DIVISOR-1:=0;
    signal din,dout:std_logic_vector(7 downto 0):=x"00";
    signal adr:std_logic_vector(1 downto 0):="00";
    signal csn,rdn,wrn,irqn:std_logic:='1';
begin
    clk<=not clk after 5 ns;
    sft<='1' when phase=0 else '0';
    process(clk) begin
        if rising_edge(clk) then
            if phase=DIVISOR-1 then phase<=0; else phase<=phase+1; end if;
        end if;
    end process;
    dut:entity work.OPNA port map(
        DIN=>din,DOUT=>dout,DOE=>open,CSn=>csn,ADR=>adr,RDn=>rdn,WRn=>wrn,INTn=>irqn,
        sndL=>open,sndR=>open,sndPSG=>open,PAOUT=>open,PAIN=>x"ff",PAOE=>open,
        PBOUT=>open,PBIN=>x"ff",PBOE=>open,RAMADDR=>open,RAMRD=>open,RAMWR=>open,
        RAMRDAT=>x"00",RAMWDAT=>open,RAMWAIT=>'0',clk=>clk,cpuclk=>clk,sft=>sft,rstn=>rstn);
    process
        procedure cycles(n:positive) is begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        procedure regwrite(regno,value:std_logic_vector(7 downto 0); target:integer:=-1) is begin
            csn<='0'; rdn<='1'; adr<="00"; din<=regno; wrn<='0';
            cycles(1); wrn<='1'; cycles(1); adr<="01"; din<=value;
            if target>=0 then
                while phase/=target loop cycles(1); end loop;
            end if;
            wrn<='0'; cycles(1); wrn<='1'; csn<='1'; cycles(1);
        end;
        procedure status is begin csn<='0'; rdn<='0'; wrn<='1'; adr<="00"; cycles(4); end;
        procedure wait_flag(bitno:natural) is begin
            status;
            for i in 1 to 40000*DIVISOR loop
                exit when dout(bitno)='1'; cycles(1);
            end loop;
            assert dout(bitno)='1' report "timer never overflowed" severity failure;
            cycles(4);
            assert irqn='0' report "timer did not assert IRQ" severity failure;
            csn<='1'; rdn<='1'; cycles(1);
        end;
    begin
        for p in 0 to DIVISOR-1 loop
            rstn<='0'; cycles(5); rstn<='1'; cycles(256);
            -- Extended status read initializes the old implementation's
            -- unreset ADPCM IRQ latch, isolating the timer-clear regression.
            csn<='0'; rdn<='0'; adr<="10"; cycles(4); csn<='1'; rdn<='1';
            regwrite(x"27",x"30"); -- stop and clear both timers
            regwrite(x"24",x"fc"); regwrite(x"25",x"00"); -- A period 16
            regwrite(x"26",x"ff"); -- B period 1 (16 A ticks)
            cycles(3500*DIVISOR); -- preload stopped counters
            regwrite(x"27",x"0a"); wait_flag(1);
            regwrite(x"27",x"2a",p); status;
            assert dout(1)='0' and irqn='1'
                report "timer B clear lost at enable phase " & integer'image(p) severity failure;
            wait_flag(1); -- a second interrupt must be possible after clear
            regwrite(x"27",x"30"); cycles(20);
            regwrite(x"27",x"05"); wait_flag(0);
            regwrite(x"27",x"15",p); status;
            assert dout(0)='0' and irqn='1'
                report "timer A clear lost at enable phase " & integer'image(p) severity failure;
            wait_flag(0);
            regwrite(x"27",x"30"); cycles(20);
            -- Both reset bits also work while no timer enable tick occurs.
        end loop;
        -- Timer clears preserve the other pending source. Reset must release
        -- IRQ without relying on a later extended-status read from software.
        regwrite(x"27",x"0f"); wait_flag(0); wait_flag(1);
        regwrite(x"27",x"1f"); status;
        assert dout(0)='0' and dout(1)='1' and irqn='0'
            report "timer A clear erased pending timer B" severity failure;
        regwrite(x"27",x"2f"); status;
        assert dout(1)='0' report "timer B selective clear failed" severity failure;
        wait_flag(0); rstn<='0'; cycles(5); rstn<='1'; cycles(256); status;
        assert dout(1 downto 0)="00" and irqn='1'
            report "reset left FM timer/IRQ state active" severity failure;
        report "PASS OPNA timer A/B one-cycle clears and repeated IRQs, divisor " & integer'image(DIVISOR) severity note;
        stop; wait;
    end process;
    process begin wait for 100 ms; assert false report "watchdog" severity failure; end process;
end;
