library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Real FEC state machine with the buffer's registered address + registered
-- output latency. The SDRAM handshake model varies its completion delay.
entity fec_buffer_tb is
    generic(CPU_MHZ: positive:=60; RAM_PHASE_PS:natural:=0;
            BUFFER_CPU_CLOCK:boolean:=false;
            BAD_EXTRA_LATENCY:boolean:=false);
end entity;
architecture test of fec_buffer_tb is
    signal clk,ramclk,buffer_clk:std_logic:='0';
    signal rstn,rd,wr,busy,brd,bwr,srd,swr,swait:std_logic:='0';
    signal ba:std_logic_vector(7 downto 0);
    signal sa:std_logic_vector(22 downto 0);
    signal q,bd,sd,wd:std_logic_vector(15 downto 0):=(others=>'0');
    signal seen:boolean:=false;
    signal remaining:natural:=0;
    signal writes,reads:natural:=0;
    signal round:natural:=0;
    type memory_t is array(0 to 255) of std_logic_vector(15 downto 0);
    function pattern(a:natural;pass:natural) return std_logic_vector is
    begin return std_logic_vector(to_unsigned((a*977+pass*12347+16#1357#) mod 65536,16)); end;
    function initial_memory return memory_t is
        variable m:memory_t;
    begin for i in m'range loop m(i):=pattern(i,0); end loop; return m; end;
    signal memory:memory_t:=initial_memory;
    signal address_reg:natural range 0 to 255:=0;
    type pipe_t is array(0 to 15) of std_logic_vector(15 downto 0);
    signal qpipe:pipe_t:=(others=>(others=>'0'));
begin
    clk<=not clk after 500 ns / CPU_MHZ;
    process begin
        wait for RAM_PHASE_PS*1 ps;
        loop wait for 5 ns;ramclk<=not ramclk;end loop;
    end process;
    buffer_clk<=clk when BUFFER_CPU_CLOCK else ramclk;
    dut:entity work.FECcont generic map(23) port map(
        HIGHADDR=>x"0257",BUFADDR=>ba,RD=>rd,WR=>wr,RDDAT=>bd,WRDAT=>q,
        BUFRD=>brd,BUFWR=>bwr,BUFWAIT=>'0',BUSY=>busy,
        SDR_ADDR=>sa,SDR_RD=>srd,SDR_WR=>swr,SDR_RDAT=>sd,
        SDR_WDAT=>wd,SDR_WAIT=>swait,clk=>clk,rstn=>rstn);
    process(buffer_clk) begin
        if rising_edge(buffer_clk) then
            if not is_x(ba) then
                address_reg<=to_integer(unsigned(ba));
                if bwr='1' then memory(to_integer(unsigned(ba)))<=bd;end if;
            end if;
            qpipe(0)<=memory(address_reg);
            for i in 1 to 15 loop qpipe(i)<=qpipe(i-1);end loop;
        end if;
    end process;
    q<=qpipe(15) when BAD_EXTRA_LATENCY else qpipe(0);
    swait<='1' when (srd='1' or swr='1') and (not seen or remaining/=0) else '0';
    process(clk)
        variable a:natural;
    begin
        if rising_edge(clk) and rstn='1' then
            if srd='0' and swr='0' then seen<=false;
            elsif not seen then
                assert srd/=swr report "ambiguous SDRAM direction" severity failure;
                a:=to_integer(unsigned(sa(7 downto 0)));
                assert sa(22 downto 8)=std_logic_vector(to_unsigned(16#257#,15))
                    report "wrong high address" severity failure;
                seen<=true;remaining<=2+(a mod 5);
                if swr='1' then
                    assert a=(writes mod 256) report "write address skipped" severity failure;
                    assert wd=pattern(a,round) report "buffer write data mismatch" severity failure;
                    writes<=writes+1;
                else
                    assert a=reads report "read address skipped" severity failure;
                    reads<=reads+1;sd<=pattern(a,1);
                end if;
            elsif remaining/=0 then remaining<=remaining-1;
            end if;
        end if;
    end process;
    process
        procedure transfer(constant reading:boolean) is
        begin
            wait until falling_edge(clk);
            if reading then rd<='1';else wr<='1';end if;
            wait until falling_edge(clk);rd<='0';wr<='0';
            wait until busy='0' for 1 ms;
            assert busy='0' report "FEC transfer watchdog" severity failure;
            wait for 200 ns;
        end;
    begin
        wait for 137 ns;rstn<='1';wait for 300 ns;
        transfer(false);assert writes=256 report "initial write count" severity failure;
        transfer(true);assert reads=256 report "read count" severity failure;
        for i in 0 to 255 loop
            assert memory(i)=pattern(i,1) report "buffer refill mismatch" severity failure;
        end loop;
        round<=1;transfer(false);
        assert writes=512 report "round-trip write count" severity failure;
        report "PASS: FEC 256-word write/refill/write at " & integer'image(CPU_MHZ) & " MHz";
        finish;
    end process;
end architecture;
