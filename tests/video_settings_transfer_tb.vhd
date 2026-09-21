library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity video_settings_transfer_tb is
    generic(CPU_MHZ:positive:=60; VIDEO_PHASE_PS:natural:=1300);
end;
architecture test of video_settings_transfer_tb is
    signal cpu_clk,video_clk,rstn:std_logic:='0';
    signal source_data,result_data:std_logic_vector(120 downto 0):=(others=>'0');
    signal checks:natural:=0;
    function pattern(n:natural) return std_logic_vector is
        variable v:std_logic_vector(15 downto 0):=std_logic_vector(to_unsigned(n,16));
        variable r:std_logic_vector(120 downto 0);
    begin
        r(15 downto 0):=v;
        for i in 16 to 120 loop
            if (i/16) mod 2=1 then r(i):=not v((i+3*(i/16)) mod 16);
            else r(i):=v((i+3*(i/16)) mod 16);end if;
        end loop;
        return r;
    end;
begin
    cpu_clk<=not cpu_clk after 500 ns/CPU_MHZ;
    process begin
        wait for VIDEO_PHASE_PS*1 ps;
        loop wait for 6667 ps;video_clk<=not video_clk;end loop;
    end process;
    dut:entity work.video_settings_transfer port map(cpu_clk,video_clk,rstn,source_data,result_data);
    process
        variable snapshot:std_logic_vector(120 downto 0);
        variable serial_number,previous:natural:=0;
    begin
        wait until rising_edge(video_clk);wait for 1 ps;
        snapshot:=result_data;
        if rstn='0' then previous:=0;
        elsif result_data/=(result_data'range=>'0') then
            serial_number:=to_integer(unsigned(result_data(15 downto 0)));
            assert result_data=pattern(serial_number) report "torn video settings snapshot" severity failure;
            assert serial_number>=previous report "video settings moved backwards" severity failure;
            previous:=serial_number;checks<=checks+1;
        end if;
        wait for 5 ns;
        if rstn='1' then
            assert result_data=snapshot report "settings changed between video edges" severity failure;
        end if;
    end process;
    process begin
        wait for 100 ns;source_data<=pattern(1);rstn<='1';
        for epoch in 1 to 2 loop
            for i in 2 to 5000 loop
                wait until falling_edge(cpu_clk);source_data<=pattern(i);
            end loop;
            wait for 1 us;
            assert result_data=pattern(5000) report "last video settings update missing" severity failure;
            if epoch=1 then
                rstn<='0';wait for 100 ns;source_data<=pattern(1);rstn<='1';
            end if;
        end loop;
        assert checks>7000 report "insufficient snapshot checks" severity failure;
        report "PASS coherent video settings: " & integer'image(checks) & " video checks, hot writes and reset";
        finish;
    end process;
end;
