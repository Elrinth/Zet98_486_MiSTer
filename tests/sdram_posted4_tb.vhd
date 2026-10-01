-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Posted four-plane CPU writes (GRCG tile writes CPUWR4 and read-modify-
-- writes CPURMW4) through the real SDRAMC, with a behavioural SDRAM that
-- stores 4-word bursts with per-beat byte masks and returns read bursts.
-- A CPU driver issues random WR4 / RMW4 / RD4 requests to a small address
-- set (request until ACK, then release) and checks every RD4 against a
-- program-order model. Reports the run time, so the posted and unposted
-- (POSTED_BITS=0) runs show the CPU-visible speed-up.
entity sdram_posted4_tb is
    generic (CPU_MHZ : positive := 90; MEM_PHASE_PS : natural := 0;
             POSTED_BITS : natural := 2; OPS : positive := 3000);
end entity;
architecture test of sdram_posted4_tb is
    constant AW : positive := 22;
    signal cpuclk, memclk : std_logic := '0';
    signal rstn, ready : std_logic := '0';
    signal address : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal bank, bytes : std_logic_vector(1 downto 0) := "11";
    signal planes : std_logic_vector(3 downto 0) := "1111";
    signal preserve : std_logic_vector(15 downto 0) := (others=>'0');
    type words_t is array(0 to 3) of std_logic_vector(15 downto 0);
    signal wd : words_t := (others=>x"0000");
    signal rdw : words_t;
    signal wr4, rmw4, rd4 : std_logic := '0';
    signal cpu_ack : std_logic;
    signal cke, cs, ras, cas, we, udq, ldq, ba1, ba0 : std_logic;
    signal ma : std_logic_vector(12 downto 0);
    signal dq : std_logic_vector(15 downto 0);
    signal read_source : std_logic_vector(15 downto 0) := (others=>'Z');
    type mem_t is array(natural range <>) of std_logic_vector(15 downto 0);
    constant SLOTS : positive := 32;
    signal sdram_words : mem_t(0 to 4*SLOTS*4-1) := (others=>x"0000");
    function slot_address(i : natural) return std_logic_vector is
        variable a : std_logic_vector(AW-1 downto 0);
    begin
        a := std_logic_vector(to_unsigned((i*40503 + (i mod 5)*1024) mod 2**AW, AW));
        a(1 downto 0) := "00";
        return a;
    end function;
    function slot_of(row : std_logic_vector(12 downto 0); col : std_logic_vector(9 downto 0)) return integer is
        variable a : std_logic_vector(AW-1 downto 0);
    begin
        for i in 0 to SLOTS-1 loop
            a := slot_address(i);
            if a(AW-1 downto AW-13)=row and a(9 downto 2)=col(9 downto 2) then return i; end if;
        end loop;
        return -1;
    end function;
begin
    cpuclk <= not cpuclk after 500 ns / CPU_MHZ;
    process begin
        wait for MEM_PHASE_PS * 1 ps;
        loop wait for 5 ns; memclk<=not memclk; end loop;
    end process;
    dq <= read_source;

    dut : entity work.SDRAMC generic map(ADRWIDTH=>AW, CLKMHZ=>100, REFCYC=>64000/8192,
        CPU_WRITE_BUNDLE=>true, SUB_WRITE_BUNDLE=>false, POSTED_WRITE_BITS=>POSTED_BITS) port map(
        PMEMCKE=>cke, PMEMCS_N=>cs, PMEMRAS_N=>ras, PMEMCAS_N=>cas,
        PMEMWE_N=>we, PMEMUDQ=>udq, PMEMLDQ=>ldq, PMEMBA1=>ba1,
        PMEMBA0=>ba0, PMEMADR=>ma, PMEMDAT=>dq,
        CPUBNK=>bank, CPUADR=>address, CPURDAT0=>rdw(0), CPURDAT1=>rdw(1),
        CPURDAT2=>rdw(2), CPURDAT3=>rdw(3), CPUWDAT0=>wd(0), CPUWDAT1=>wd(1),
        CPUWDAT2=>wd(2), CPUWDAT3=>wd(3), CPUPRESERVE=>preserve,
        CPUWR1=>'0', CPUWR4=>wr4, CPURD1=>'0', CPURD4=>rd4, CPURMW1=>'0', CPURMW4=>rmw4,
        CPUBSEL=>bytes, CPUPSEL=>planes, CPUACK=>cpu_ack, CPUCLK=>cpuclk,
        SUBBNK=>"00", SUBADR=>(others=>'0'), SUBRDAT0=>open, SUBRDAT1=>open,
        SUBRDAT2=>open, SUBRDAT3=>open, SUBWDAT0=>x"0000", SUBWDAT1=>x"0000",
        SUBWDAT2=>x"0000", SUBWDAT3=>x"0000",
        SUBWR1=>'0', SUBWR4=>'0', SUBRD1=>'0', SUBRD4=>'0', SUBRMW1=>'0', SUBRMW4=>'0',
        SUBBSEL=>"00", SUBPSEL=>"0000", SUBACK=>open, SUBCLK=>cpuclk,
        VIDBNK=>"00", VIDADR=>(others=>'0'), VIDDAT0=>open, VIDDAT1=>open,
        VIDDAT2=>open, VIDDAT3=>open, VIDRD=>'0', VIDACK=>open, VIDCLK=>cpuclk,
        FDERDAT=>open, FDEWAIT=>open, FDECLK=>cpuclk,
        FECRDAT=>open, FECWAIT=>open, FECCLK=>cpuclk,
        mem_inidone=>ready, memclk=>memclk, rstn=>rstn
    );

    -- Behavioural SDRAM: open row per bank; a WRITE starts a 4-beat burst at
    -- its column (beats on consecutive cycles, per-beat byte masks); a READ
    -- returns 4 words from CAS latency 2.
    process
        type rows_t is array(0 to 3) of std_logic_vector(12 downto 0);
        variable open_row : rows_t := (others=>(others=>'0'));
        variable b, wb : natural range 0 to 3;
        variable slot, wslot : integer;
        variable beat : integer := 4;
        variable col, wcol : std_logic_vector(9 downto 0);
        variable word : std_logic_vector(15 downto 0);
        variable idx : natural;
        variable bank_bits : std_logic_vector(1 downto 0);
    begin
        wait until falling_edge(memclk);
        if rstn='1' and ready='1' then
            if beat < 4 and not (cs='0' and (ras='0' or cas='0')) then
                idx := (wb*SLOTS + wslot)*4 + ((to_integer(unsigned(wcol(1 downto 0))) + beat) mod 4);
                word := sdram_words(idx);
                if ldq='0' then word(7 downto 0) := dq(7 downto 0); end if;
                if udq='0' then word(15 downto 8) := dq(15 downto 8); end if;
                sdram_words(idx) <= word;
                beat := beat + 1;
            else
                beat := 4;
            end if;
            if cs='0' then
                bank_bits := ba1 & ba0;
                b := to_integer(unsigned(bank_bits));
                if ras='0' and cas='1' and we='1' then
                    open_row(b) := ma;
                elsif ras='1' and cas='0' then
                    col := ma(9 downto 0);
                    slot := slot_of(open_row(b), col);
                    assert slot>=0 report "SDRAM access outside the test address set" severity failure;
                    if we='0' then
                        wb := b; wslot := slot; wcol := col;
                        idx := (b*SLOTS + slot)*4 + to_integer(unsigned(col(1 downto 0)));
                        word := sdram_words(idx);
                        if ldq='0' then word(7 downto 0) := dq(7 downto 0); end if;
                        if udq='0' then word(15 downto 8) := dq(15 downto 8); end if;
                        sdram_words(idx) <= word;
                        beat := 1;
                    else
                        idx := (b*SLOTS + slot)*4;
                        read_source <= sdram_words(idx) after 20 ns, sdram_words(idx+1) after 30 ns,
                                       sdram_words(idx+2) after 40 ns, sdram_words(idx+3) after 50 ns,
                                       (others=>'Z') after 60 ns;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process
        variable model : mem_t(0 to 4*SLOTS*4-1) := (others=>x"0000");
        variable seed : natural := 4242;
        variable i, b, key, kind : natural;
        variable p : std_logic_vector(3 downto 0);
        variable sel : std_logic_vector(1 downto 0);
        variable keep : std_logic_vector(15 downto 0);
        variable value : words_t;
        variable merged : std_logic_vector(15 downto 0);
        variable reads, writes, rmws : natural := 0;
        impure function rnd(n : positive) return natural is
        begin
            seed := (seed * 25173 + 13849) mod 65536;
            return (seed / 16) mod n;
        end function;
        procedure request_and_wait is
        begin
            loop
                wait until rising_edge(cpuclk);
                exit when cpu_ack='1';
            end loop;
            wait until falling_edge(cpuclk);
            wr4<='0'; rmw4<='0'; rd4<='0';
            wait until falling_edge(cpuclk);
        end procedure;
    begin
        wait for 137 ns; rstn<='1';
        wait until ready='1';
        wait for 300 ns;
        for op in 0 to OPS-1 loop
            wait until falling_edge(cpuclk);
            i := rnd(SLOTS); b := rnd(4); key := (b*SLOTS + i)*4;
            address <= slot_address(i);
            bank <= std_logic_vector(to_unsigned(b, 2));
            kind := rnd(10);
            if kind < 7 then
                p := std_logic_vector(to_unsigned(1 + rnd(15), 4));
                case rnd(3) is
                    when 0 => sel := "01";
                    when 1 => sel := "10";
                    when others => sel := "11";
                end case;
                for k in 0 to 3 loop value(k) := std_logic_vector(to_unsigned(rnd(65536), 16)); end loop;
                if kind < 4 then keep := x"0000"; else keep := std_logic_vector(to_unsigned(rnd(65536), 16)); end if;
                planes <= p; bytes <= sel; wd <= value; preserve <= keep;
                if kind < 4 then wr4 <= '1'; writes := writes + 1;
                else rmw4 <= '1'; rmws := rmws + 1; end if;
                for k in 0 to 3 loop
                    if p(k)='1' then
                        merged := value(k) or (model(key+k) and keep);
                        if sel(0)='1' then model(key+k)(7 downto 0) := merged(7 downto 0); end if;
                        if sel(1)='1' then model(key+k)(15 downto 8) := merged(15 downto 8); end if;
                    end if;
                end loop;
                request_and_wait;
            else
                planes <= "1111"; bytes <= "11"; preserve <= x"0000"; rd4 <= '1';
                request_and_wait;
                for k in 0 to 3 loop
                    assert rdw(k) = model(key+k)
                        report "RD4 after posted writes: slot " & to_string(key/4) & " plane " &
                            to_string(k) & " got " & to_hstring(rdw(k)) & " expected " &
                            to_hstring(model(key+k)) severity failure;
                end loop;
                reads := reads + 1;
            end if;
        end loop;
        for k in 0 to 4*SLOTS-1 loop
            wait until falling_edge(cpuclk);
            address <= slot_address(k mod SLOTS);
            bank <= std_logic_vector(to_unsigned(k / SLOTS, 2));
            planes <= "1111"; bytes <= "11"; rd4 <= '1';
            request_and_wait;
            for j in 0 to 3 loop
                assert rdw(j) = model(k*4+j)
                    report "final RD4 slot " & to_string(k) & " plane " & to_string(j) &
                        " got " & to_hstring(rdw(j)) & " expected " & to_hstring(model(k*4+j)) severity failure;
            end loop;
        end loop;
        report "PASS posted four-plane writes: " & to_string(writes) & " WR4, " &
            to_string(rmws) & " RMW4, " & to_string(reads) & " RD4 + " &
            to_string(4*SLOTS) & " final reads, CPU " & to_string(CPU_MHZ) & " MHz, FIFO 2**" &
            to_string(POSTED_BITS) & ", " & to_string(now / 1 ns) & " ns" severity note;
        stop;
        wait;
    end process;
end architecture;
