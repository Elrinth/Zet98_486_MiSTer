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

-- The text GDC's SYNC active-lines parameter (P7/P8) selects the 480-line
-- display: AL above 400 sets LINES480, 400 or reset clears it.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity txtgdc_lines480_tb is end;
architecture test of txtgdc_lines480_tb is
    signal clk,rstn,cs,wr:std_logic:='0';
    signal addr:std_logic_vector(2 downto 0):="000";
    signal din:std_logic_vector(7 downto 0):=x"00";
    signal lines480:std_logic;
    signal done:boolean:=false;
    type bytes is array(natural range <>) of std_logic_vector(7 downto 0);
begin
    clk<=not clk after 5 ns when not done else '0';
    dut:entity work.TXTGDC port map(CS=>cs,ADDR=>addr,RD=>'0',WR=>wr,DIN=>din,DOUT=>open,DOE=>open,
        LPEND=>'0',VRTC=>'0',HRTC=>'0',
        ATRSEL=>open,C40=>open,GRMONO=>open,FONTSEL=>open,GRPMODE=>open,KACMODE=>open,
        NVMWPROT=>open,DISPEN=>open,COLORMODE=>open,EGCEN=>open,GDCCLK=>open,GDCCLK2=>open,
        CUREN=>open,CHARLINES=>open,BLRATE=>open,CURBLINK=>open,CURUPPER=>open,CURLOWER=>open,
        VIDEN=>open,SAD0=>open,SAD1=>open,SAD2=>open,SAD3=>open,SL0=>open,SL1=>open,SL2=>open,SL3=>open,
        PITCH=>open,EAD=>open,LINES480=>lines480,clk=>clk,rstn=>rstn);
    process
        procedure put(command:boolean; value:std_logic_vector(7 downto 0)) is
        begin
            if command then addr<="001"; else addr<="000"; end if;
            din<=value;cs<='1';wr<='1';
            for i in 1 to 3 loop wait until rising_edge(clk); end loop;
            wr<='0';cs<='0';
            for i in 1 to 12 loop wait until rising_edge(clk); end loop;
        end procedure;
        procedure sync(p:bytes) is
        begin
            put(true,x"0e");
            for i in p'range loop put(false,p(i)); end loop;
            for i in 1 to 40 loop wait until rising_edge(clk); end loop;
        end procedure;
    begin
        wait for 50 ns;rstn<='1';
        for i in 1 to 10 loop wait until rising_edge(clk); end loop;
        assert lines480='0' report "480-line mode set after reset" severity failure;
        sync((x"10",x"4e",x"4b",x"0c",x"03",x"06",x"e0",x"95"));     -- AL = 480
        assert lines480='1' report "SYNC AL=480 did not select 480 lines" severity failure;
        sync((x"10",x"4e",x"47",x"0c",x"07",x"0d",x"90",x"89"));     -- AL = 400
        assert lines480='0' report "SYNC AL=400 kept 480 lines" severity failure;
        sync((x"10",x"4e",x"4b",x"0c",x"03",x"0b",x"db",x"95"));     -- AL = 475
        assert lines480='1' report "SYNC AL=475 (480/25-row) not 480-line" severity failure;
        -- other commands and fewer parameters leave it unchanged
        put(true,x"47");put(false,x"50");
        put(true,x"0e");put(false,x"10");put(false,x"4e");
        for i in 1 to 40 loop wait until rising_edge(clk); end loop;
        assert lines480='1' report "partial SYNC changed the line count" severity failure;
        rstn<='0';wait for 20 ns;rstn<='1';
        for i in 1 to 5 loop wait until rising_edge(clk); end loop;
        assert lines480='0' report "reset kept 480 lines" severity failure;
        report "PASS text GDC SYNC active lines select 640x480 (480/475) and 640x400";
        done<=true;wait;
    end process;
end;
