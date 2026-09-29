-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Posted CPU word writes through the real SDRAMC with a behavioural SDRAM
-- that stores what is written (bank, row, column, byte masks) and returns it
-- on reads. A CPU driver issues random word writes and reads to a small
-- address set, like the PC-98 bus (request until ACK, then release), and
-- checks every read against a program-order reference model. Posted writes
-- must land with the right bytes, and a read must see every older write.
entity sdram_posted_tb is
    generic (CPU_MHZ : positive := 90; MEM_PHASE_PS : natural := 0;
             POSTED_BITS : natural := 3; OPS : positive := 4000);
end entity;
architecture test of sdram_posted_tb is
    constant AW : positive := 22;
    signal cpuclk, memclk : std_logic := '0';
    signal rstn, ready : std_logic := '0';
    signal address : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal bank, bytes : std_logic_vector(1 downto 0) := "00";
    signal wdat : std_logic_vector(15 downto 0) := (others=>'0');
    signal wr1, rd1 : std_logic := '0';
    signal cpu_ack : std_logic;
    signal cpu_rd0 : std_logic_vector(15 downto 0);
    signal cke, cs, ras, cas, we, udq, ldq, ba1, ba0 : std_logic;
    signal ma : std_logic_vector(12 downto 0);
    signal dq : std_logic_vector(15 downto 0);
    signal read_source : std_logic_vector(15 downto 0) := (others=>'Z');
    -- Behavioural array, indexed by {bank, row, column} of the small test set.
    type mem_t is array(natural range <>) of std_logic_vector(15 downto 0);
    constant SLOTS : positive := 64;
    signal sdram_words : mem_t(0 to 4*SLOTS-1) := (others=>x"0000");
    signal posted_writes, sdram_writes : natural := 0;
    function slot_address(i : natural) return std_logic_vector is
    begin  -- spread over rows and columns; column bits 9..0, row bits 21..9
        return std_logic_vector(to_unsigned((i*40503 + (i mod 7)*1024) mod 2**AW, AW));
    end function;
    function slot_of(b : std_logic_vector(1 downto 0); row : std_logic_vector(12 downto 0);
                     col : std_logic_vector(9 downto 0)) return integer is
        variable a : std_logic_vector(AW-1 downto 0);
    begin
        for i in 0 to SLOTS-1 loop
            a := slot_address(i);
            if a(AW-1 downto AW-13)=row and a(9 downto 0)=col then
                return to_integer(unsigned(b))*SLOTS + i;
            end if;
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
        CPUBNK=>bank, CPUADR=>address, CPURDAT0=>cpu_rd0, CPURDAT1=>open,
        CPURDAT2=>open, CPURDAT3=>open, CPUWDAT0=>wdat, CPUWDAT1=>x"0000",
        CPUWDAT2=>x"0000", CPUWDAT3=>x"0000", CPUPRESERVE=>x"0000",
        CPUWR1=>wr1, CPUWR4=>'0', CPURD1=>rd1, CPURD4=>'0', CPURMW1=>'0', CPURMW4=>'0',
        CPUBSEL=>bytes, CPUPSEL=>"0001", CPUACK=>cpu_ack, CPUCLK=>cpuclk,
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

    -- Behavioural SDRAM: open row per bank, masked word writes, reads return
    -- the stored word with the same timing as sdram_request_tb.
    process
        type rows_t is array(0 to 3) of std_logic_vector(12 downto 0);
        variable open_row : rows_t := (others=>(others=>'0'));
        variable b : natural range 0 to 3;
        variable slot : integer;
        variable word : std_logic_vector(15 downto 0);
    begin
        wait until falling_edge(memclk);
        if rstn='1' and ready='1' and cs='0' then
            b := to_integer(unsigned(std_logic_vector'(ba1 & ba0)));
            if ras='0' and cas='1' and we='1' then
                open_row(b) := ma;                         -- ACTIVATE
            elsif ras='1' and cas='0' then
                slot := slot_of(ba1 & ba0, open_row(b), ma(9 downto 0));
                assert slot>=0 report "SDRAM access outside the test address set: bank " &
                    integer'image(b) & " row " & to_hstring(open_row(b)) & " col " &
                    to_hstring(ma(9 downto 0)) & " we " & std_logic'image(we) & " ma " & to_hstring(ma) severity failure;
                if we='0' then                              -- WRITE
                    word := sdram_words(slot);
                    if ldq='0' then word(7 downto 0) := dq(7 downto 0); end if;
                    if udq='0' then word(15 downto 8) := dq(15 downto 8); end if;
                    sdram_words(slot) <= word;
                    sdram_writes <= sdram_writes + 1;
                else                                        -- READ
                    read_source <= sdram_words(slot) after 20 ns, (others=>'Z') after 30 ns;
                end if;
            end if;
        end if;
    end process;

    process
        variable model : mem_t(0 to 4*SLOTS-1) := (others=>x"0000");
        variable seed : natural := 12345;
        variable i, b, key : natural;
        variable sel : std_logic_vector(1 downto 0);
        variable value, expect : std_logic_vector(15 downto 0);
        variable reads, writes, cycles, t0 : natural := 0;
        impure function rnd(n : positive) return natural is
        begin
            seed := (seed * 25173 + 13849) mod 65536;   -- stays within 32-bit integers
            return (seed / 16) mod n;
        end function;
        procedure request_and_wait is
        begin
            loop
                wait until rising_edge(cpuclk);
                exit when cpu_ack='1';
            end loop;
            wait until falling_edge(cpuclk);
            wr1<='0'; rd1<='0';
            wait until falling_edge(cpuclk);           -- bridge RELEASE state
        end procedure;
    begin
        wait for 137 ns; rstn<='1';
        wait until ready='1';
        wait for 300 ns;
        for op in 0 to OPS-1 loop
            wait until falling_edge(cpuclk);
            i := rnd(SLOTS); b := rnd(4); key := b*SLOTS + i;
            address <= slot_address(i);
            bank <= std_logic_vector(to_unsigned(b, 2));
            if rnd(10) < 7 then
                case rnd(3) is
                    when 0 => sel := "01";
                    when 1 => sel := "10";
                    when others => sel := "11";
                end case;
                value := std_logic_vector(to_unsigned(rnd(65536), 16));
                bytes <= sel; wdat <= value; wr1 <= '1';
                if sel(0)='1' then model(key)(7 downto 0) := value(7 downto 0); end if;
                if sel(1)='1' then model(key)(15 downto 8) := value(15 downto 8); end if;
                request_and_wait;
                writes := writes + 1;
            else
                bytes <= "11"; rd1 <= '1';
                request_and_wait;
                expect := model(key);
                assert cpu_rd0 = expect
                    report "read after posted writes: slot " & integer'image(key) &
                        " got " & to_hstring(cpu_rd0) & " expected " & to_hstring(expect)
                    severity failure;
                reads := reads + 1;
            end if;
        end loop;
        -- Drain: one final read of every slot sees the program-order value.
        for k in 0 to 4*SLOTS-1 loop
            wait until falling_edge(cpuclk);
            address <= slot_address(k mod SLOTS);
            bank <= std_logic_vector(to_unsigned(k / SLOTS, 2));
            bytes <= "11"; rd1 <= '1';
            request_and_wait;
            assert cpu_rd0 = model(k)
                report "final read slot " & integer'image(k) & " got " & to_hstring(cpu_rd0) &
                    " expected " & to_hstring(model(k)) severity failure;
        end loop;
        assert sdram_writes = writes report "posted write count mismatch: " &
            integer'image(sdram_writes) & " SDRAM writes for " & integer'image(writes) severity failure;
        report "PASS posted SDRAM writes: " & integer'image(writes) & " writes, " &
            integer'image(reads) & " interleaved reads + " & integer'image(4*SLOTS) &
            " final reads, CPU " & integer'image(CPU_MHZ) & " MHz, FIFO 2**" &
            integer'image(POSTED_BITS) & ", " & integer'image(now / 1 ns) & " ns" severity note;
        stop;
        wait;
    end process;
end architecture;
