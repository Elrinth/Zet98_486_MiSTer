library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity grpal_video_tb is
    generic(CPU_MHZ:positive:=60; VIDEO_PHASE_PS:natural:=1300);
end entity;
architecture test of grpal_video_tb is
    signal clk,video_clk:std_logic:='0';
    signal rstn,cs,wr,rd,colormode:std_logic:='0';
    signal addr:std_logic_vector(1 downto 0):="00";
    signal num:std_logic_vector(3 downto 0):=x"0";
    signal wd,rdata,refdata:std_logic_vector(7 downto 0):=x"00";
    signal r,g,b,rr,rg,rb:std_logic_vector(3 downto 0);
    signal doe,refdoe:std_logic;
    signal checking:boolean:=false;
    signal checks:natural:=0;
begin
    clk<=not clk after 500 ns / CPU_MHZ;
    process begin
        wait for VIDEO_PHASE_PS*1 ps;
        loop wait for 6667 ps;video_clk<=not video_clk;end loop;
    end process;
    dut:entity work.grpal generic map(VIDEO_STAGED=>true) port map(
        CS=>cs,ADDR=>addr,WR=>wr,RD=>rd,WRDAT=>wd,RDDAT=>rdata,DOE=>doe,
        COLORMODE=>colormode,NUMIN=>num,vidR=>r,vidG=>g,vidB=>b,
        clk=>clk,rstn=>rstn,video_clk=>video_clk);
    reference:entity work.grpal_legacy port map(
        CS=>cs,ADDR=>addr,WR=>wr,RD=>rd,WRDAT=>wd,RDDAT=>refdata,DOE=>refdoe,
        COLORMODE=>colormode,NUMIN=>num,vidR=>rr,vidG=>rg,vidB=>rb,
        clk=>clk,rstn=>rstn);
    process
        variable expected:std_logic_vector(11 downto 0);
    begin
        wait until rising_edge(video_clk);
        expected:=rr & rg & rb;
        wait for 1 ps;
        if checking then
            assert (r & g & b)=expected report "staged palette differs" severity failure;
            checks<=checks+1;
        end if;
        -- NUMIN stays unchanged until the video falling edge. CPU writes
        -- between sample and that edge must not change the video palette.
        wait for 5 ns;
        if checking then
            assert (r & g & b)=expected report "staged palette differs between video edges" severity failure;
        end if;
    end process;
    process begin
        wait until falling_edge(video_clk);
        num<=std_logic_vector(unsigned(num)+1);
    end process;
    process begin
        wait until rising_edge(clk);wait for 1 ps;
        assert rdata=refdata and doe=refdoe report "CPU palette readback changed" severity failure;
    end process;
    process
        variable random:unsigned(31 downto 0):=x"98c01234";
    begin
        wait for 100 ns;rstn<='1';wait for 100 ns;checking<=true;
        for i in 0 to 9999 loop
            wait until falling_edge(clk);
            random:=random xor shift_left(random,13);
            random:=random xor shift_right(random,17);
            random:=random xor shift_left(random,5);
            cs<=random(0);wr<=random(1);rd<=random(2);colormode<=random(3);
            wd<=std_logic_vector(random(15 downto 8));addr<=std_logic_vector(random(5 downto 4));
            -- Include reset while switching modes and programming palettes.
            if i=5000 then rstn<='0';else rstn<='1';end if;
        end loop;
        wait for 100 ns;
        assert checks>7000 report "not enough palette pixel checks" severity failure;
        report "PASS: staged palette and original CPU readback, " & integer'image(checks) & " pixel checks";
        finish;
    end process;
end architecture;
