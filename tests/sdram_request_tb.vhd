library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Exercise the actual controller's CPU request path and SDRAM command pins.
-- The tiny read-data source supplies varied bursts; it is not a SDRAM
-- electrical/timing model. Addresses, byte/plane masks, live RMW write data,
-- completion and request count are checked independently of the controller.
entity sdram_request_tb is
    generic (CPU_MHZ : positive := 50; BUFFERED : boolean := false;
             MEM_PHASE_PS : natural := 0; USE_SUB : boolean := false;
             HOLD_COMPLETION_CYCLES : natural := 0;
             AFFINE_TEST : boolean := false; AFFINE_CASES : positive := 16384);
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
    signal expected_rd : words_t;
    signal preserve_mask : std_logic_vector(15 downto 0) := x"0000";
    signal affine : std_logic := '0';
    signal xor_masks : std_logic_vector(63 downto 0) := (others=>'0');
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
begin
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
    assert not AFFINE_TEST or (BUFFERED and not USE_SUB)
        report "Affine test requires buffered CPU port" severity failure;
    dut : entity work.SDRAMC generic map(ADRWIDTH=>AW, CLKMHZ=>100, REFCYC=>64000/8192,
        CPU_WRITE_BUNDLE=>BUFFERED and not USE_SUB, SUB_WRITE_BUNDLE=>BUFFERED and USE_SUB,
        CPU_AFFINE_RMW=>AFFINE_TEST) port map(
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
        mem_inidone=>ready, memclk=>memclk, rstn=>rstn, CPUAFFINE=>affine, CPUXORMASK=>xor_masks
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
        variable a, r, w, beats, total : natural;
        variable rowcol : unsigned(AW-1 downto 0);
        variable mask, value, read_value : std_logic_vector(15 downto 0);
        variable source_value, pattern_value, result_value, base_value : std_logic_vector(15 downto 0);
        variable coefficients : std_logic_vector(63 downto 0);
        variable operation : std_logic_vector(7 downto 0);
        variable tests_in_mode, case_id, zero_index, actual_index : natural;
        variable chosen_bytes : std_logic_vector(1 downto 0);
        variable chosen_planes : std_logic_vector(3 downto 0);
        variable affine_case : boolean;
    begin
        wait for 137 ns; rstn<='1';
        wait until ready='1';
        wait for 300 ns;
        total:=0;
        for mode in 0 to 5 loop
            tests_in_mode:=64;
            if AFFINE_TEST and mode=5 then tests_in_mode:=AFFINE_CASES+64; end if;
            for n in 0 to tests_in_mode-1 loop
                affine_case:=AFFINE_TEST and mode=5 and n<AFFINE_CASES;
                -- Odd multiplier permutes all operation/plane/byte tuples
                -- and gives the shorter clock sweeps varied active masks.
                case_id:=(n*4051) mod 16384;
                if AFFINE_TEST and (mode/=5 or affine_case) then affine<='1'; else affine<='0'; end if;
                wait until falling_edge(cpuclk);
                rowcol:=to_unsigned((n*1031+mode*131071) mod 2**AW,AW);
                -- Four-plane operations use plane-aligned addresses in Zet98.
                if mode=1 or mode=3 or mode=5 then rowcol(1 downto 0):="00"; end if;
                expected_address<=std_logic_vector(rowcol); address<=std_logic_vector(rowcol);
                expected_bank<=std_logic_vector(to_unsigned(n mod 4,2)); bank<=std_logic_vector(to_unsigned(n mod 4,2));
                if affine_case then
                    chosen_bytes:=std_logic_vector(to_unsigned((case_id/4096) mod 4,2));
                    chosen_planes:=std_logic_vector(to_unsigned((case_id/256) mod 16,4));
                else
                    chosen_bytes:=std_logic_vector(to_unsigned((n/4) mod 4,2));
                    chosen_planes:=std_logic_vector(to_unsigned(n mod 16,4));
                end if;
                expected_bytes<=chosen_bytes; bytes<=chosen_bytes;
                expected_planes<=chosen_planes; planes<=chosen_planes;
                mask:=x"0000";
                if BUFFERED and mode>=4 then mask:=std_logic_vector(to_unsigned((n*1031) mod 65536,16)); end if;
                preserve_mask<=mask;
                coefficients:=(others=>'1');
                operation:=std_logic_vector(to_unsigned(case_id mod 256,8));
                for p in 0 to 3 loop
                    value:=std_logic_vector(to_unsigned((n*8191+p*4369+mode*349) mod 65536,16));
                    read_value:=std_logic_vector(to_unsigned((n*977+p*12347+mode*3181) mod 65536,16));
                    expected_rd(p)<=read_value;
                    wd(p)<=value;
                    -- A one-word RMW only refreshes plane zero; other write
                    -- outputs are unused. Four-plane RMW refreshes all four.
                    expected_wd(p)<=value or (read_value and mask);
                    if affine_case then
                        source_value:=std_logic_vector(to_unsigned((n*193+p*8191+13469) mod 65536,16));
                        pattern_value:=std_logic_vector(to_unsigned((n*977+p*2731+4951) mod 65536,16));
                        base_value:=(others=>'0'); result_value:=read_value;
                        for bit_no in 0 to 15 loop
                            if chosen_planes(p)='1' and chosen_bytes(bit_no/8)='1' and mask(bit_no)='1' then
                                zero_index:=0;
                                if source_value(bit_no)='1' then zero_index:=zero_index+4; end if;
                                if pattern_value(bit_no)='1' then zero_index:=zero_index+1; end if;
                                base_value(bit_no):=operation(zero_index);
                                coefficients(p*16+bit_no):=operation(zero_index) xor operation(zero_index+2);
                                actual_index:=zero_index;
                                if read_value(bit_no)='1' then actual_index:=actual_index+2; end if;
                                -- Independent full truth-table oracle.
                                result_value(bit_no):=operation(actual_index);
                            end if;
                        end loop;
                        wd(p)<=base_value; expected_wd(p)<=result_value;
                    end if;
                end loop;
                xor_masks<=coefficients;
                kind<=mode; active<=true;
                a:=activations; r:=reads; w:=writes; beats:=write_beats;
                requests(mode)<='1';
                if AFFINE_TEST then
                    wait until rising_edge(cpuclk); wait for 1 ns;
                    -- Coefficients and mode must come from the held
                    -- request, not live pins after acceptance.
                    xor_masks<=not xor_masks; affine<=not affine;
                    preserve_mask<=not preserve_mask;
                    wd<=(x"c1a5",x"39f0",x"95ac",x"7e13");
                end if;
                if USE_SUB and BUFFERED then
                    wait until rising_edge(cpuclk); wait for 1 ns;
                    -- Poison all live metadata after request acceptance.
                    -- SDRAM must keep the original bank/address/masks.
                    address<=not address; bank<=not bank;
                    bytes<=not bytes; planes<=not planes;
                end if;
                if mode>=4 then
                    wait until reads>r;
                    -- The actual GRCG computes new data after the SDRAM read.
                    wait for 15 ns;
                    wd<=(x"c1a5",x"39f0",x"95ac",x"7e13");
                end if;
                wait until ack='1' for 3 us;
                assert ack='1' report "SDRAM request timed out" severity failure;
                wait for 1 ps;
                if mode>=2 then
                    assert rd(0)=expected_rd(0) report "read data missing on ACK edge" severity failure;
                    if mode=3 or mode=5 then
                        assert rd=expected_rd report "four-plane data missing on ACK edge" severity failure;
                    end if;
                end if;
                wait until falling_edge(cpuclk);
                wait for 1 ps; -- settle coincident memory-edge output assignments
                assert activations=a+1 report "duplicated or missing activation" severity failure;
                if mode>=2 then
                    assert reads=r+1 and rd(0)=expected_rd(0) report "read completion mismatch" severity failure;
                    if mode=3 or mode=5 then
                        assert rd=expected_rd
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
                -- A completed request held on the bus must not replay its
                -- completion or issue another SDRAM command. CPU completion
                -- is a pulse; drawing completion stays held until release.
                for hold_cycle in 1 to HOLD_COMPLETION_CYCLES loop
                    wait until rising_edge(cpuclk); wait for 1 ps;
                    if USE_SUB then
                        assert ack='1' report "drawing ACK released before strobe" severity failure;
                    else
                        assert ack='0' report "CPU completion repeated" severity failure;
                    end if;
                    assert activations=a+1 report "held request repeated" severity failure;
                    if mode>=2 then
                        assert rd(0)=expected_rd(0) report "held read data changed" severity failure;
                    end if;
                end loop;
                requests<=(others=>'0'); active<=false;
                if ack/='0' then wait until ack='0'; end if;
                -- Minimum bus-release spacing used by the CPU bridge.
                wait until falling_edge(cpuclk);
                total:=total+1;
            end loop;
        end loop;
        if AFFINE_TEST then
            assert total=AFFINE_CASES+384 report "Affine case count changed" severity failure;
            report "PASS: affine SDRAM " & natural'image(AFFINE_CASES) &
                " raster operations plus 384 compatibility requests, live coefficients poisoned";
        end if;
        report "PASS: SDRAM request metadata at " & integer'image(CPU_MHZ) &
            " MHz, SUB=" & boolean'image(USE_SUB) & ": " & integer'image(total) & " single/four-plane read/write/RMW commands, masks, live RMW data";
        finish;
    end process;
    process begin wait for 100 ms; assert false report "SDRAM request watchdog" severity failure; end process;
end architecture;
