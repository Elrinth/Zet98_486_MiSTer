-- SPDX-License-Identifier: GPL-3.0-or-later
-- Text GDC CSRR (E0h). The NEC MS-DOS console driver sends E0h to port 62h,
-- then polls port 60h for DATA READY before reading five bytes. CSRR has no
-- parameters, so the data must be ready without any further write
-- (Hello Gre's SHOTANM otherwise waits forever).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
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
use std.env.all;
entity text_gdc_csrr_tb is end;
architecture test of text_gdc_csrr_tb is
    signal clk:std_logic:='0'; signal rstn:std_logic:='0';
    signal cs,rd,wr:std_logic:='0';
    signal addr:std_logic_vector(2 downto 0):="000";
    signal din,dout:std_logic_vector(7 downto 0):=x"00";
    signal doe:std_logic;
begin
    clk<=not clk after 5 ns;
    dut:entity work.TXTGDC port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,DIN=>din,DOUT=>dout,DOE=>doe,
        LPEND=>'0',VRTC=>'0',HRTC=>'0',
        ATRSEL=>open,C40=>open,GRMONO=>open,FONTSEL=>open,GRPMODE=>open,KACMODE=>open,
        NVMWPROT=>open,DISPEN=>open,COLORMODE=>open,EGCEN=>open,GDCCLK=>open,GDCCLK2=>open,
        CUREN=>open,CHARLINES=>open,BLRATE=>open,CURBLINK=>open,CURUPPER=>open,CURLOWER=>open,
        VIDEN=>open,SAD0=>open,SAD1=>open,SAD2=>open,SAD3=>open,SL0=>open,SL1=>open,SL2=>open,SL3=>open,
        PITCH=>open,EAD=>open,DISPAW=>open,DISPAL=>open,clk=>clk,rstn=>rstn);
    process
        procedure cycles(n:positive) is begin
            for i in 1 to n loop wait until falling_edge(clk); end loop;
        end;
        -- ports 60h/62h: ADDR 000 = parameter/status, 001 = command/data
        procedure put(a:std_logic;v:std_logic_vector(7 downto 0)) is begin
            addr<="00"&a; din<=v; cs<='1'; wr<='1'; cycles(2);
            cs<='0'; wr<='0'; cycles(6);
        end;
        procedure get(a:std_logic;v:out std_logic_vector(7 downto 0)) is begin
            addr<="00"&a; cs<='1'; rd<='1'; cycles(2); v:=dout;
            cs<='0'; rd<='0'; cycles(4);
        end;
        variable b:std_logic_vector(7 downto 0);
        variable ready:boolean;
    begin
        cycles(3); rstn<='1'; cycles(3);
        put('1',x"49"); put('0',x"34"); put('0',x"12");   -- CSRW EAD=1234h
        put('1',x"e0");                                    -- CSRR, no parameters
        ready:=false;
        for i in 1 to 100 loop
            get('0',b);
            if b(0)='1' then ready:=true; exit; end if;
        end loop;
        assert ready report "CSRR: DATA READY never set (console driver hangs)" severity failure;
        get('1',b); assert b=x"34" report "CSRR byte 0 is not EAD low" severity failure;
        get('1',b); assert b=x"12" report "CSRR byte 1 is not EAD high" severity failure;
        get('1',b); get('1',b); get('1',b);
        get('0',b); assert b(0)='0' report "DATA READY still set after five bytes" severity failure;
        report "PASS: text GDC CSRR returns the cursor address without parameters";
        finish;
    end process;
end;
