-- SPDX-License-Identifier: GPL-3.0-or-later
-- uPD71054 (8254) read-back and unlatched reads on the PC-98 PIT. Win95
-- Setup's MPU-401 probe (MSDET.DLL) times its CLI delays by writing D2h
-- (read-back, latch counter 0) to port 77h and reading the count from 71h
-- until it wraps; the PIT ignored read-back and every read returned the
-- last 8253 latch, so detection hung at 98% with interrupts off.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity pit_readback_tb is end;
architecture test of pit_readback_tb is
    signal clk:std_logic:='0'; signal rstn:std_logic:='0';
    signal cs,rd,wr:std_logic:='0';
    signal addr:std_logic_vector(1 downto 0):="00";
    signal wdat,rdat:std_logic_vector(7 downto 0):=x"00";
    signal doe:std_logic;
    signal cntin:std_logic_vector(2 downto 0):="000";
    signal cntout:std_logic_vector(2 downto 0);
begin
    clk<=not clk after 5 ns;
    dut:entity work.PTC8253 port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,RDAT=>rdat,WDAT=>wdat,DOE=>doe,
        CNTIN=>cntin,TRIG=>"000",CNTOUT=>cntout,clk=>clk,rstn=>rstn);
    process
        procedure cycles(n:positive) is begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        procedure put(a:std_logic_vector(1 downto 0); v:std_logic_vector(7 downto 0)) is begin
            addr<=a; wdat<=v; cs<='1'; wr<='1'; cycles(1); cs<='0'; wr<='0'; cycles(2);
        end;
        procedure get(a:std_logic_vector(1 downto 0); v:out std_logic_vector(7 downto 0)) is begin
            addr<=a; cs<='1'; rd<='1'; cycles(2); v:=rdat; cs<='0'; rd<='0'; cycles(2);
        end;
        procedure get16(v:out natural) is
            variable l,h:std_logic_vector(7 downto 0);
        begin
            get("00",l); get("00",h); v:=to_integer(unsigned(h & l));
        end;
        procedure ticks(n:positive) is begin
            for i in 1 to n loop cntin(0)<='1'; cycles(1); cntin(0)<='0'; cycles(1); end loop;
        end;
        variable a,b,c,old,new_v,wraps,polls:natural;
        variable s:std_logic_vector(7 downto 0);
    begin
        cycles(3); rstn<='1'; cycles(3);
        -- counter 0, LSB/MSB, mode 2, count 1000
        put("11",x"34"); put("00",x"E8"); put("00",x"03");
        ticks(10); get16(a); ticks(5); get16(b);
        assert a=990 and b=985 report "unlatched reads: " & integer'image(a) & ", " & integer'image(b) &
            " (expected the running count 990, 985)" severity failure;
        -- 8253 counter latch still holds until both bytes are read
        put("11",x"00"); ticks(3); get16(a); get16(b);
        assert a=985 and b=982 report "counter latch: " & integer'image(a) & ", then " & integer'image(b) severity failure;
        -- read-back D2h: latch counter 0's count only
        put("11",x"D2"); ticks(7); get16(a); get16(b);
        assert a=982 and b=975 report "read-back count latch: " & integer'image(a) & ", then " & integer'image(b) severity failure;
        -- read-back E2h: status only; count loaded, LSB/MSB, mode 2, binary =
        -- x0110100 (bit 7 is OUT, which this model's mode 2 holds low)
        put("11",x"E2"); get("00",s);
        assert s(6 downto 0)="0110100" report "read-back status " & to_hstring(s) & ", expected 34/B4" severity failure;
        get16(a);
        assert a=975 report "status read moved the LSB/MSB flip-flop: " & integer'image(a) severity failure;
        -- read-back C2h: status, then the latched count
        put("11",x"C2"); ticks(4); get("00",s); get16(a);
        assert s(6 downto 0)="0110100" and a=975 report "read-back status+count: " & to_hstring(s) & " " & integer'image(a) severity failure;
        -- other counters' select bits leave counter 0 alone
        put("11",x"DC"); get16(a); ticks(1); get16(b);
        assert b=a-1 report "read-back of counters 1-2 latched counter 0" severity failure;
        -- MSDET.DLL's CLI delay: D2h, read 71h twice; a count above the last
        -- one is a reload. Two reloads of a count of 20 must come within 60 polls.
        put("11",x"34"); put("00",x"14"); put("00",x"00");
        put("11",x"D2"); get16(old); wraps:=0; polls:=0;
        while wraps<2 and polls<60 loop
            ticks(1);
            put("11",x"D2"); get16(new_v);
            if new_v>old then wraps:=wraps+1; end if;
            old:=new_v; polls:=polls+1;
        end loop;
        assert wraps=2 report "MSDET read-back delay never saw the counter reload" severity failure;
        report "PASS: PIT read-back count/status latches, unlatched reads see the running count, MSDET delay terminates";
        finish;
    end process;
end;
