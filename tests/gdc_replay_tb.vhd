-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Same registered read-address latency as the production gdcfifo M9K wrapper.
entity gdcfifo is
    port(clock:in std_logic;data:in std_logic_vector(8 downto 0);
         rdaddress,wraddress:in std_logic_vector(3 downto 0);
         wren:in std_logic;q:out std_logic_vector(8 downto 0));
end;
architecture model of gdcfifo is
    type ram_t is array(0 to 15) of std_logic_vector(8 downto 0);
    signal ram:ram_t:=(others=>(others=>'0'));
    signal ra:integer range 0 to 15:=0;
begin
    process(clock) begin if rising_edge(clock) then
        ra<=to_integer(unsigned(rdaddress));
        if wren='1' then ram(to_integer(unsigned(wraddress)))<=data;end if;
    end if;end process;
    q<=ram(ra);
end;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
-- Replays a logged graphics-GDC command stream ("c XX" command, "p XX"
-- parameter, hex) into GRAGDC with a request/ACK memory model and checks that
-- every FIGD/drawing command finishes (status bit 3 DRAWING clears).
entity gdc_replay_tb is
    generic (STREAM:string:="tests/data_totsugeki_gdc.txt"; WLOG:string:="gdc_writes.txt"; ACK_DELAY:natural:=2; LIMIT:natural:=400000);
end;
architecture test of gdc_replay_tb is
    signal clk,rstn,cs,wr,rd:std_logic:='0';signal done:boolean:=false;
    signal addr:std_logic_vector(1 downto 0):="00";
    signal din,dout,pitch:std_logic_vector(7 downto 0):=(others=>'0');
    signal ma:std_logic_vector(17 downto 0);
    signal wd:std_logic_vector(15 downto 0);
    signal mr,mw,ack:std_logic:='0';
    signal writes,reads:natural:=0;
begin
    clk<=not clk after 5 ns when not done;
    dut:entity work.GRAGDC port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,DIN=>din,DOUT=>dout,DOE=>open,
        LPEND=>'0',VRTC=>'0',HRTC=>'0',VRAMSEL=>open,CRAMSEL=>open,INTR=>open,GRAPHEN=>open,VZOOM=>open,
        BASEADDR0=>open,BASEADDR1=>open,SL0=>open,SL1=>open,
        BASEADDR2=>open,BASEADDR3=>open,SL2=>open,SL3=>open,IM=>open,PITCH=>pitch,DOTPLINE=>open,
        GDC_ADDR=>ma,GDC_RDAT=>x"0000",GDC_WDAT=>wd,GDC_RD=>mr,GDC_WR=>mw,GDC_MACK=>ack,clk=>clk,rstn=>rstn);
    process(clk)
        variable ticks:natural:=0;
        file wf:text open write_mode is WLOG;
        variable wl:line;
    begin if rising_edge(clk) then
        if mr='0' and mw='0' then ack<='0';ticks:=0;
        elsif ack='0' then
            if ticks=ACK_DELAY then
                ack<='1';
                if mw='1' then writes<=writes+1;
                    write(wl,to_hstring(ma));write(wl,string'(" "));write(wl,to_hstring(wd));writeline(wf,wl);
                else reads<=reads+1;end if;
            else ticks:=ticks+1;end if;
        end if;
    end if;end process;
    process
        file f:text open read_mode is STREAM;
        variable l:line;variable kind:character;variable sp:character;variable v:std_logic_vector(7 downto 0);
        variable n,before,draws:natural:=0;variable st:std_logic_vector(7 downto 0);
        procedure send(command:boolean;val:std_logic_vector(7 downto 0)) is begin
            wait until falling_edge(clk);cs<='1';wr<='1';din<=val;
            if command then addr<="01";else addr<="00";end if;
            wait until falling_edge(clk);wait until falling_edge(clk);wr<='0';
            for d in 1 to 15 loop wait until falling_edge(clk);end loop;
            cs<='0';
        end;
        procedure status(s:out std_logic_vector(7 downto 0)) is begin
            wait until falling_edge(clk);cs<='1';rd<='1';addr<="00";
            wait until falling_edge(clk);wait until falling_edge(clk);s:=dout;
            rd<='0';cs<='0';wait until falling_edge(clk);
        end;
    begin
        wait for 101 ns;rstn<='1';wait for 100 ns;
        send(true,x"47");send(false,x"28");
        while not endfile(f) loop
            readline(f,l);read(l,kind);read(l,sp);hread(l,v);
            n:=n+1;
            if kind='c' then
                before:=writes;
                send(true,v);
                if v=x"6c" then
                    draws:=draws+1;
                    for t in 1 to LIMIT loop
                        status(st);
                        exit when st(3)='0' and mr='0' and mw='0';
                        assert t<LIMIT report "draw " & integer'image(draws) & " (line " & integer'image(n) &
                            ") never finished: status " & to_hstring(st) & " writes " & integer'image(writes-before) severity failure;
                    end loop;
                    report "draw " & integer'image(draws) & " done, " & integer'image(writes-before) & " VRAM writes";
                end if;
            else
                send(false,v);
            end if;
        end loop;
        report "PASS: " & integer'image(draws) & " drawing commands finished";
        done<=true;wait;
    end process;
end;
