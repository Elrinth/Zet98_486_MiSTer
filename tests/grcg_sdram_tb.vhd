library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Connect the production GRCG to both SDRAM client ports and check the
-- comparison on the ACK edge. A command-level burst source supplies four
-- distinct planes; this is not an SDRAM electrical/timing model.
entity grcg_sdram_tb is
    generic (CPU_MHZ : positive := 50; BUFFERED : boolean := false;
             MEM_PHASE_PS : natural := 0; USE_SUB : boolean := false;
             HOLD_COMPLETION_CYCLES : natural := 0);
end entity;
architecture test of grcg_sdram_tb is
    constant AW : positive := 22;
    signal cpuclk, memclk : std_logic := '0';
    signal rstn, ready, ack : std_logic := '0';
    signal address : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal bank, bytes : std_logic_vector(1 downto 0) := "00";
    signal planes : std_logic_vector(3 downto 0) := "0000";
    signal requests : std_logic_vector(5 downto 0) := (others=>'0');
    type words_t is array(0 to 3) of std_logic_vector(15 downto 0);
    signal wd : words_t := (others=>x"1357");
    signal expected_wd : words_t;
    signal expected_rd : words_t;
    signal preserve_mask : std_logic_vector(15 downto 0) := x"0000";
    signal rd, cpu_rd, sub_rd : words_t;
    signal cpu_req, sub_req : std_logic_vector(5 downto 0);
    signal cpu_ack, sub_ack : std_logic;
    signal cke, cs, ras, cas, we, udq, ldq, ba1, ba0 : std_logic;
    signal ma : std_logic_vector(12 downto 0);
    signal dq : std_logic_vector(15 downto 0);
    signal read_source : std_logic_vector(15 downto 0) := (others=>'Z');
    signal expected_address : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal expected_bank, expected_bytes : std_logic_vector(1 downto 0) := "00";
    signal expected_planes : std_logic_vector(3 downto 0) := "0000";
    signal kind : natural range 0 to 5 := 0;
    signal active : boolean := false;
    signal activations, reads, writes, write_beats : natural := 0;
    signal g_iocs,g_ioaddr,g_iowr,g_read : std_logic := '0';
    signal g_data : std_logic_vector(7 downto 0) := x"00";
    signal g_result : std_logic_vector(15 downto 0);
begin
    graphics : entity work.grcg generic map(SPLIT_RMW=>true) port map(
        iocs=>g_iocs,ioaddr=>g_ioaddr,iowr=>g_iowr,iowdat=>g_data,
        pmemcs=>'1',ppsel=>address(1 downto 0),prd=>g_read,pwr=>'0',
        prddat=>g_result,pwrdat=>x"0000",poe=>open,
        memrd1=>requests(2),memrd4=>requests(3),memwr1=>requests(0),
        memwr4=>requests(1),memrmw1=>requests(4),memrmw4=>requests(5),
        memrdat0=>rd(0),memrdat1=>rd(1),memrdat2=>rd(2),memrdat3=>rd(3),
        memwdat0=>open,memwdat1=>open,memwdat2=>open,memwdat3=>open,
        memwmask=>open,memwrpsel=>open,clk=>cpuclk,rstn=>rstn);
    cpuclk <= not cpuclk after 500 ns / CPU_MHZ;
    process begin
        wait for MEM_PHASE_PS * 1 ps;
        loop wait for 5 ns; memclk<=not memclk; end loop;
    end process;
    dq <= read_source;
    cpu_req <= requests when not USE_SUB else (others=>'0');
    sub_req <= requests when USE_SUB else (others=>'0');
    ack <= sub_ack when USE_SUB else cpu_ack;
    rd <= sub_rd when USE_SUB else cpu_rd;
    dut : entity work.SDRAMC generic map(AW,100,64000/8192,BUFFERED and not USE_SUB,BUFFERED and USE_SUB) port map(
        PMEMCKE=>cke, PMEMCS_N=>cs, PMEMRAS_N=>ras, PMEMCAS_N=>cas,
        PMEMWE_N=>we, PMEMUDQ=>udq, PMEMLDQ=>ldq, PMEMBA1=>ba1,
        PMEMBA0=>ba0, PMEMADR=>ma, PMEMDAT=>dq,
        CPUBNK=>bank, CPUADR=>address, CPURDAT0=>cpu_rd(0), CPURDAT1=>cpu_rd(1),
        CPURDAT2=>cpu_rd(2), CPURDAT3=>cpu_rd(3), CPUWDAT0=>wd(0), CPUWDAT1=>wd(1),
        CPUWDAT2=>wd(2), CPUWDAT3=>wd(3), CPUPRESERVE=>preserve_mask,
        CPUWR1=>cpu_req(0), CPUWR4=>cpu_req(1),
        CPURD1=>cpu_req(2), CPURD4=>cpu_req(3), CPURMW1=>cpu_req(4), CPURMW4=>cpu_req(5),
        CPUBSEL=>bytes, CPUPSEL=>planes, CPUACK=>cpu_ack, CPUCLK=>cpuclk,
        SUBBNK=>bank, SUBADR=>address, SUBRDAT0=>sub_rd(0), SUBRDAT1=>sub_rd(1),
        SUBRDAT2=>sub_rd(2), SUBRDAT3=>sub_rd(3), SUBWDAT0=>wd(0), SUBWDAT1=>wd(1),
        SUBWDAT2=>wd(2), SUBWDAT3=>wd(3), SUBPRESERVE=>preserve_mask,
        SUBWR1=>sub_req(0), SUBWR4=>sub_req(1), SUBRD1=>sub_req(2), SUBRD4=>sub_req(3),
        SUBRMW1=>sub_req(4), SUBRMW4=>sub_req(5), SUBBSEL=>bytes,
        SUBPSEL=>planes, SUBACK=>sub_ack, SUBCLK=>cpuclk,
        VIDBNK=>"00", VIDADR=>(others=>'0'), VIDDAT0=>open, VIDDAT1=>open,
        VIDDAT2=>open, VIDDAT3=>open, VIDRD=>'0', VIDACK=>open, VIDCLK=>cpuclk,
        FDERDAT=>open, FDEWAIT=>open, FDECLK=>cpuclk,
        FECRDAT=>open, FECWAIT=>open, FECCLK=>cpuclk,
        mem_inidone=>ready, memclk=>memclk, rstn=>rstn
    );

    process
        variable burst_left : natural range 0 to 3 := 0;
        variable lane : natural range 0 to 3 := 0;
        variable want_bytes : std_logic_vector(1 downto 0);
        variable column : std_logic_vector(9 downto 0);
    begin
        wait until falling_edge(memclk);
        if rstn='1' and ready='1' then
            if cs='0' and ras='0' and cas='1' and we='1' then
                assert active report "unsolicited SDRAM activation" severity failure;
                assert ma=expected_address(AW-1 downto AW-13) and
                       (ba1 & ba0)=expected_bank report "SDRAM row/bank mismatch" severity failure;
                activations<=activations+1;
            end if;
            if cs='0' and ras='1' and cas='0' then
                assert active report "unsolicited SDRAM column command" severity failure;
                column:=expected_address(9 downto 0);
                if kind=1 or kind=3 or (kind=5 and we='1') then column(1 downto 0):="00"; end if;
                assert ma(9 downto 0)=column and (ba1 & ba0)=expected_bank
                    report "SDRAM column/bank mismatch" severity failure;
                if we='1' then
                    assert kind>=2 report "unexpected SDRAM read" severity failure;
                    assert (udq & ldq)=std_logic_vector'("00") report "read masked unexpectedly" severity failure;
                    reads<=reads+1;
                    if kind=2 or kind=4 then
                        read_source<=expected_rd(0) after 20 ns, (others=>'Z') after 30 ns;
                    else
                        read_source<=expected_rd(0) after 20 ns, expected_rd(1) after 30 ns,
                            expected_rd(2) after 40 ns, expected_rd(3) after 50 ns,
                            (others=>'Z') after 60 ns;
                    end if;
                else
                    assert kind/=2 and kind/=3 report "unexpected SDRAM write" severity failure;
                    writes<=writes+1;
                    if kind=1 or kind=5 then burst_left:=3; else burst_left:=0; end if;
                    lane:=0;
                end if;
            elsif burst_left>0 then
                lane:=4-burst_left;
                burst_left:=burst_left-1;
            else
                lane:=0;
            end if;
            if (cs='0' and ras='1' and cas='0' and we='0') or lane>0 then
                want_bytes:=expected_bytes;
                if (kind=1 or kind=5) and expected_planes(lane)='0' then want_bytes:="00"; end if;
                assert (udq & ldq)=not want_bytes report "SDRAM write mask mismatch" severity failure;
                assert (BUFFERED and dq=expected_wd(lane)) or (not BUFFERED and dq=wd(lane))
                    report "SDRAM write data mismatch mode=" & integer'image(kind) &
                    " lane=" & integer'image(lane) & " actual=" & to_hstring(dq) severity failure;
                write_beats<=write_beats+1;
            end if;
            lane:=0;
        end if;
    end process;

    process
        constant tiles : words_t := (x"5a5a",x"c3c3",x"9696",x"0f0f");
        variable before_reads,before_activations,total : natural := 0;
        variable values : words_t;
        variable expected : std_logic_vector(15 downto 0);
        variable subset : unsigned(3 downto 0);
        variable rowcol : unsigned(AW-1 downto 0);
        procedure out_port(tile : boolean; value : std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(cpuclk);
            g_iocs<='1'; g_iowr<='1'; g_data<=value;
            if tile then g_ioaddr<='1'; else g_ioaddr<='0'; end if;
            wait until falling_edge(cpuclk); g_iowr<='0';
            wait until falling_edge(cpuclk);
        end;
    begin
        wait for 137 ns; rstn<='1';
        wait until ready='1'; wait for 300 ns;
        for mode in 0 to 2 loop
            for n in 0 to 63 loop
                subset:=to_unsigned(n mod 16,4);
                case mode is
                    when 0 => out_port(false,x"8" & std_logic_vector(not subset)); kind<=3;
                    when 1 => out_port(false,x"00"); kind<=2;
                    when others => out_port(false,x"c0"); kind<=2;
                end case;
                for p in 0 to 3 loop out_port(true,tiles(p)(7 downto 0)); end loop;
                wait until falling_edge(cpuclk);
                -- Include every addressed plane. READ4 must align its SDRAM
                -- column internally; callers need not force plane zero.
                rowcol:=to_unsigned((n*1031+mode*131071) mod 2**AW,AW);
                address<=std_logic_vector(rowcol); expected_address<=std_logic_vector(rowcol);
                bank<=std_logic_vector(to_unsigned(n mod 4,2));
                expected_bank<=std_logic_vector(to_unsigned(n mod 4,2));
                bytes<=std_logic_vector(to_unsigned((n/4) mod 4,2));
                for p in 0 to 3 loop
                    values(p):=tiles(p) xor std_logic_vector(to_unsigned((n*977+p*12347) mod 65536,16));
                end loop;
                expected_rd<=values;
                expected:=(others=>'1');
                for bit_no in 0 to 15 loop
                    for p in 0 to 3 loop
                        if subset(p)='1' and values(p)(bit_no)/=tiles(p)(bit_no) then
                            expected(bit_no):='0';
                        end if;
                    end loop;
                end loop;
                if mode/=0 then expected:=values(0); end if;
                active<=true; before_reads:=reads; before_activations:=activations;
                g_read<='1';
                wait until ack='1' for 3 us;
                assert ack='1' report "GRCG SDRAM request timed out" severity failure;
                wait for 1 ps;
                assert g_result=expected report "GRCG SDRAM result missing on ACK" severity failure;
                wait until falling_edge(cpuclk);
                assert reads=before_reads+1 and activations=before_activations+1
                    report "GRCG SDRAM read replayed" severity failure;
                assert writes=0 report "GRCG SDRAM read wrote memory" severity failure;
                g_read<='0'; active<=false;
                if ack/='0' then wait until ack='0'; end if;
                wait until falling_edge(cpuclk); total:=total+1;
            end loop;
        end loop;
        report "PASS GRCG/SDRAM: " & natural'image(total) &
            " ACK-edge results at " & positive'image(CPU_MHZ) &
            " MHz, SUB=" & boolean'image(USE_SUB) & ", phase=" & natural'image(MEM_PHASE_PS);
        finish;
    end process;
    process begin wait for 3 ms; assert false report "GRCG SDRAM watchdog" severity failure; end process;
end architecture;
