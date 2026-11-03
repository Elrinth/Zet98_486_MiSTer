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
-- The graphics GDC's display enable follows START/BCTRL and SYNC's DE bit
-- (uPD7220; NP2kai io/gdc.c). Libros de Chilam Balam turns its graphics on
-- with a bare SYNC 0Fh. SYNC parameters must not change the display state.
entity gdc_sync_tb is
end;
architecture test of gdc_sync_tb is
    signal clk,rstn,cs,wr:std_logic:='0';signal done:boolean:=false;
    signal addr:std_logic_vector(1 downto 0):="00";
    signal din,dout,pitch:std_logic_vector(7 downto 0):=(others=>'0');
    signal b0,b1:std_logic_vector(17 downto 0);
    signal l0,l1,l2,l3:std_logic_vector(9 downto 0);
    signal b2,b3:std_logic_vector(13 downto 0);
    signal ma:std_logic_vector(17 downto 0);
    signal wd:std_logic_vector(15 downto 0);
    signal mr,mw:std_logic;
    signal en:std_logic;
begin
    clk<=not clk after 5 ns when not done;
    dut:entity work.GRAGDC port map(CS=>cs,ADDR=>addr,RD=>'0',WR=>wr,DIN=>din,DOUT=>dout,DOE=>open,
        LPEND=>'0',VRTC=>'0',HRTC=>'0',VRAMSEL=>open,CRAMSEL=>open,INTR=>open,GRAPHEN=>en,VZOOM=>open,
        BASEADDR0=>b0,BASEADDR1=>b1,SL0=>l0,SL1=>l1,
        BASEADDR2=>b2,BASEADDR3=>b3,SL2=>l2,SL3=>l3,IM=>open,PITCH=>pitch,DOTPLINE=>open,
        GDC_ADDR=>ma,GDC_RDAT=>x"0000",GDC_WDAT=>wd,GDC_RD=>mr,GDC_WR=>mw,GDC_MACK=>'1',clk=>clk,rstn=>rstn);
    process
        procedure send(command:boolean;v:natural) is begin
            wait until falling_edge(clk);cs<='1';wr<='1';din<=std_logic_vector(to_unsigned(v,8));
            if command then addr<="01";else addr<="00";end if;
            wait until falling_edge(clk);wait until falling_edge(clk);wr<='0';
            for delay in 1 to 15 loop wait until falling_edge(clk);end loop;
            cs<='0';
            for delay in 1 to 20 loop wait until falling_edge(clk);end loop;
        end;
        procedure expect(v:std_logic;what:string) is begin
            assert en=v report what & ": GRAPHEN=" & std_logic'image(en) severity failure;
        end;
    begin
        rstn<='0';wait for 31 ns;rstn<='1';wait for 100 ns;
        send(true,16#0d#);expect('1',"BCTRL 0Dh");
        send(true,16#0e#);expect('0',"SYNC 0Eh");
        send(true,16#0f#);expect('1',"bare SYNC 0Fh");
        send(true,16#0c#);expect('0',"BCTRL 0Ch");
        -- SYNC with its eight parameters (a 640x400 set): only DE counts
        send(true,16#0f#);
        for i in 0 to 7 loop send(false,16#10#+i);end loop;
        expect('1',"SYNC 0Fh with parameters");
        send(true,16#0e#);
        for i in 0 to 7 loop send(false,16#20#+i);end loop;
        expect('0',"SYNC 0Eh with parameters");
        send(true,16#6b#);expect('1',"START 6Bh");
        send(true,16#47#);send(false,40);expect('1',"PITCH keeps the display on");
        done<=true;
        report "PASS graphics GDC display enable follows START, BCTRL and SYNC";
        wait;
    end process;
end;
