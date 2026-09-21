library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Exercise the actual controller's CPU request path and SDRAM command pins.
-- The tiny read-data source supplies a constant burst; it is not a SDRAM
-- electrical/timing model. Addresses, byte/plane masks, live RMW write data,
-- completion and request count are checked independently of the controller.
entity sdram_request_tb is
    generic (CPU_MHZ : positive := 50; BUFFERED : boolean := false;
             MEM_PHASE_PS : natural := 0);
end entity;
architecture test of sdram_request_tb is
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
    signal preserve_mask : std_logic_vector(15 downto 0) := x"0000";
    signal rd : words_t;
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
begin
    cpuclk <= not cpuclk after 500 ns / CPU_MHZ;
    process begin
        wait for MEM_PHASE_PS * 1 ps;
        loop wait for 5 ns; memclk<=not memclk; end loop;
    end process;
    dq <= read_source;
    dut : entity work.SDRAMC generic map(AW,100,64000/8192,BUFFERED) port map(
        PMEMCKE=>cke, PMEMCS_N=>cs, PMEMRAS_N=>ras, PMEMCAS_N=>cas,
        PMEMWE_N=>we, PMEMUDQ=>udq, PMEMLDQ=>ldq, PMEMBA1=>ba1,
        PMEMBA0=>ba0, PMEMADR=>ma, PMEMDAT=>dq,
        CPUBNK=>bank, CPUADR=>address, CPURDAT0=>rd(0), CPURDAT1=>rd(1),
        CPURDAT2=>rd(2), CPURDAT3=>rd(3), CPUWDAT0=>wd(0), CPUWDAT1=>wd(1),
        CPUWDAT2=>wd(2), CPUWDAT3=>wd(3), CPUPRESERVE=>preserve_mask,
        CPUWR1=>requests(0), CPUWR4=>requests(1),
        CPURD1=>requests(2), CPURD4=>requests(3), CPURMW1=>requests(4), CPURMW4=>requests(5),
        CPUBSEL=>bytes, CPUPSEL=>planes, CPUACK=>ack, CPUCLK=>cpuclk,
        SUBBNK=>"00", SUBADR=>(others=>'0'), SUBRDAT0=>open, SUBRDAT1=>open,
        SUBRDAT2=>open, SUBRDAT3=>open, SUBWDAT0=>x"0000", SUBWDAT1=>x"0000",
        SUBWDAT2=>x"0000", SUBWDAT3=>x"0000", SUBWR1=>'0', SUBWR4=>'0',
        SUBRD1=>'0', SUBRD4=>'0', SUBRMW1=>'0', SUBRMW4=>'0', SUBBSEL=>"00",
        SUBPSEL=>"0000", SUBACK=>open, SUBCLK=>cpuclk,
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
                        read_source<=x"a55a" after 20 ns, (others=>'Z') after 30 ns;
                    else
                        read_source<=x"a55a" after 20 ns, (others=>'Z') after 60 ns;
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
        variable a, r, w, beats, total : natural;
        variable rowcol : unsigned(AW-1 downto 0);
        variable mask, value : std_logic_vector(15 downto 0);
    begin
        wait for 137 ns; rstn<='1';
        wait until ready='1';
        wait for 300 ns;
        total:=0;
        for mode in 0 to 5 loop
            for n in 0 to 63 loop
                wait until falling_edge(cpuclk);
                rowcol:=to_unsigned((n*1031+mode*131071) mod 2**AW,AW);
                -- Four-plane operations use plane-aligned addresses in Zet98.
                if mode=1 or mode=3 or mode=5 then rowcol(1 downto 0):="00"; end if;
                expected_address<=std_logic_vector(rowcol); address<=std_logic_vector(rowcol);
                expected_bank<=std_logic_vector(to_unsigned(n mod 4,2)); bank<=std_logic_vector(to_unsigned(n mod 4,2));
                expected_bytes<=std_logic_vector(to_unsigned((n/4) mod 4,2)); bytes<=std_logic_vector(to_unsigned((n/4) mod 4,2));
                expected_planes<=std_logic_vector(to_unsigned(n mod 16,4)); planes<=std_logic_vector(to_unsigned(n mod 16,4));
                mask:=x"0000";
                if BUFFERED and mode>=4 then mask:=std_logic_vector(to_unsigned((n*1031) mod 65536,16)); end if;
                preserve_mask<=mask;
                for p in 0 to 3 loop
                    value:=std_logic_vector(to_unsigned((n*8191+p*4369+mode*349) mod 65536,16));
                    wd(p)<=value;
                    expected_wd(p)<=value or (x"a55a" and mask);
                end loop;
                kind<=mode; active<=true;
                a:=activations; r:=reads; w:=writes; beats:=write_beats;
                requests(mode)<='1';
                if mode>=4 then
                    wait until reads>r;
                    -- The actual GRCG computes new data after the SDRAM read.
                    wait for 15 ns;
                    wd<=(x"c1a5",x"39f0",x"95ac",x"7e13");
                end if;
                wait until ack='1' for 3 us;
                assert ack='1' report "SDRAM request timed out" severity failure;
                wait until falling_edge(cpuclk);
                wait for 1 ps; -- settle coincident memory-edge output assignments
                assert activations=a+1 report "duplicated or missing activation" severity failure;
                if mode>=2 then
                    assert reads=r+1 and rd(0)=x"a55a" report "read completion mismatch" severity failure;
                    if mode=3 or mode=5 then
                        assert rd(1)=x"a55a" and rd(2)=x"a55a" and rd(3)=x"a55a"
                            report "four-plane read data mismatch: " & to_hstring(rd(0)) & " " & to_hstring(rd(1)) & " " & to_hstring(rd(2)) & " " & to_hstring(rd(3)) severity failure;
                    end if;
                else assert reads=r report "write performed extra read" severity failure; end if;
                if mode=2 or mode=3 then
                    assert writes=w and write_beats=beats report "read performed extra write" severity failure;
                else
                    assert writes=w+1 report "duplicated or missing write command" severity failure;
                    if mode=1 or mode=5 then
                        assert write_beats=beats+4 report "four-plane write length mismatch" severity failure;
                    else assert write_beats=beats+1 report "word write length mismatch" severity failure; end if;
                end if;
                requests<=(others=>'0'); active<=false;
                if ack/='0' then wait until ack='0'; end if;
                -- Minimum bus-release spacing used by the CPU bridge.
                wait until falling_edge(cpuclk);
                total:=total+1;
            end loop;
        end loop;
        report "PASS: SDRAM request metadata at " & integer'image(CPU_MHZ) &
            " MHz: " & integer'image(total) & " single/four-plane read/write/RMW commands, masks, live RMW data";
        finish;
    end process;
    process begin wait for 3 ms; assert false report "SDRAM request watchdog" severity failure; end process;
end architecture;
