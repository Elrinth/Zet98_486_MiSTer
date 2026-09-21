library ieee;
use ieee.std_logic_1164.all;
entity graphbuf816 is
    port(clock : in std_logic; data : in std_logic_vector(15 downto 0);
         rdaddress : in std_logic_vector(6 downto 0);
         wraddress : in std_logic_vector(5 downto 0); wren : in std_logic;
         q : out std_logic_vector(7 downto 0));
end entity;
architecture test of graphbuf816 is
begin q <= (others=>'0'); end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity crtc_reset_render_tb is end;
architecture test of crtc_reset_render_tb is
    signal clk, raw_rstn, rstn, pixel_clk, de : std_logic := '0';
    signal running : boolean := true;
    signal done : boolean := false;
    signal r,g,b : std_logic_vector(3 downto 0);
    signal base : std_logic_vector(12 downto 0) := (others=>'0');
    signal pitch : std_logic_vector(7 downto 0) := (others=>'0');
    signal lines : std_logic_vector(4 downto 0) := (others=>'0');
begin
    process begin
        wait for 6667 ps;
        if done then wait;
        elsif running then clk<=not clk;
        else clk<='0'; end if;
    end process;
    parent_reset : entity work.reset_release port map(clk,raw_rstn,rstn);
    dut : entity work.CRTC98 port map(
        TRAM_ADR=>open,TRAM_DAT=>x"0041",TRAM_ATR=>x"e1",
        KNJSEL=>open,KNJADR=>open,KNJDAT=>x"ff",
        GRAMADR=>open,GRAMRD=>open,GRAMACK=>'0',
        GRAMDAT0=>x"0000",GRAMDAT1=>x"0000",GRAMDAT2=>x"0000",GRAMDAT3=>x"0000",
        ETRAM_ADR=>open,ETRAM_DAT=>x"00",ECURL=>"00000",ECURC=>"0000000",ECUREN=>'0',
        ROUT=>r,GOUT=>g,BOUT=>b,HSYNC=>open,VSYNC=>open,VIDEOEN=>de,
        TBASEADDR=>base,HMODE=>'1',VLINES=>lines,TPITCH=>pitch,
        GRAPHEN=>'0',DOTPLINE=>"00000",LOWBL=>'0',GCOLOR=>'1',MONOSEL=>"0000",TXTEN=>'1',
        CURADDR=>(others=>'0'),CURE=>'0',CURUPPER=>0,CURLOWER=>15,CBLINK=>'0',BLINKRATE=>"01000",
        GBASEADDR0=>(others=>'0'),GBASEADDR1=>(others=>'0'),
        GLINENUM0=>(others=>'0'),GLINENUM1=>(others=>'0'),GPITCH=>x"28",
        EMUMODE=>'0',VRTC=>open,HRTC=>open,GPALNO=>open,GPALR=>x"0",GPALG=>x"0",GPALB=>x"0",
        gclk=>pixel_clk,clk=>clk,rstn=>rstn);
    process
        variable count,white : natural;
    begin
        for phase in 0 to 5 loop
            raw_rstn<='0';
            -- Change settings during reset, including once with no clock.
            base<=std_logic_vector(to_unsigned(phase*80,13));pitch<=x"50";lines<="01111";
            if phase=5 then running<=false;wait for 100 ns;end if;
            wait for (phase*7997+17)*1 ps;
            raw_rstn<='1';
            if phase=5 then
                wait for 100 ns;
                assert rstn='0' report "Parent reset released with stopped clock" severity failure;
                running<=true;
            end if;
            wait until de='1' for 35 ms;
            assert de='1' report "CRTC failed to produce visible pixels after reset" severity failure;
            count:=0;white:=0;
            while de='1' loop
                wait until falling_edge(pixel_clk);
                if de='1' then
                    assert not is_x(r & g & b) report "Uninitialized CRTC pixel" severity failure;
                    count:=count+1;
                    if (r & g & b)=x"fff" then white:=white+1;end if;
                end if;
            end loop;
            assert count=640 report "Wrong visible line width: " & integer'image(count) severity failure;
            assert white>=624 report "Text settings failed after reset: " & integer'image(white) severity failure;
            report "PASS CRTC reset/render phase " & integer'image(phase) & ": 640 pixels, white=" & integer'image(white);
        end loop;
        done<=true;wait;
    end process;
    process begin wait until done for 250 ms;assert done report "CRTC watchdog" severity failure;wait;end process;
end;
