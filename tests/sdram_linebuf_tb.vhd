-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Main-RAM line buffer in front of the real SDRAMC (posted CPU writes, CPURD4
-- fills) with a behavioural SDRAM that stores writes and returns four-word
-- bursts. The CPU side copies ao486_memory_bridge: strobe until ACK (data
-- sampled on that edge), RELEASE until ACK is low, then IDLE for a clock
-- before the next request; the second half of a dword goes straight from
-- RELEASE to the next transfer. Wired as Zet98MiSTer.vhd: every CPU-port
-- write snoops the buffer, the buffer takes CPUACK as its fill acknowledge,
-- and the CPU sees CPUACK or the buffer's hit acknowledge.
-- Random byte/word writes, word reads, read-modify-write pairs and dword
-- pairs on a few four-word groups are checked against program order.
entity sdram_linebuf_tb is
    generic (CPU_MHZ : positive := 90; MEM_PHASE_PS : natural := 0;
             POSTED_BITS : natural := 3;
             OPS : positive := 20000; SEED : positive := 12345; SNOOP_ON : std_logic := '1';
             AFFINE : boolean := true; VIDEO : boolean := true);
end entity;
architecture test of sdram_linebuf_tb is
    constant AW : positive := 22;
    signal cpuclk, memclk, pixclk : std_logic := '0';
    signal vid_rd, vid_ack : std_logic := '0';
    signal vid_adr : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal rstn, ready : std_logic := '0';
    signal address : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal bank, bytes : std_logic_vector(1 downto 0) := "00";
    signal wdat : std_logic_vector(15 downto 0) := (others=>'0');
    signal mwr, mrd : std_logic := '0';
    signal sdr_ack, cpu_ack : std_logic;
    signal rd0, rd1, rd2, rd3 : std_logic_vector(15 downto 0);
    signal buf_rd4, buf_ack, buf_doe : std_logic;
    signal buf_rdat, cpu_rdat, buf_rdath : std_logic_vector(15 downto 0);
    signal buf_dw : std_logic;
    signal cke, cs, ras, cas, we, udq, ldq, ba1, ba0 : std_logic;
    signal ma : std_logic_vector(12 downto 0);
    signal dq : std_logic_vector(15 downto 0);
    signal read_source : std_logic_vector(15 downto 0) := (others=>'Z');
    type mem_t is array(natural range <>) of std_logic_vector(15 downto 0);
    constant GROUPS : positive := 12;
    constant SLOTS : positive := 4*GROUPS;
    signal sdram_words : mem_t(0 to 4*SLOTS-1) := (others=>x"0000");
    -- Word i of the test set: groups spread over rows and columns, four
    -- consecutive words per group (one CPURD4 line).
    function slot_address(i : natural) return std_logic_vector is
        variable g : natural := i / 4;
    begin
        return std_logic_vector(to_unsigned(((g*40503 + (g mod 5)*1024) mod 2**AW) / 4 * 4 + i mod 4, AW));
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
    pixclk <= not pixclk after 23.75 ns;
    process begin
        wait for MEM_PHASE_PS * 1 ps;
        loop wait for 5 ns; memclk<=not memclk; end loop;
    end process;
    dq <= read_source;

    dut : entity work.SDRAMC generic map(ADRWIDTH=>AW, CLKMHZ=>100, REFCYC=>64000/8192,
        CPU_WRITE_BUNDLE=>true, SUB_WRITE_BUNDLE=>true, FLOPPY_REQUEST_BUNDLE=>true,
        CPU_AFFINE_RMW=>AFFINE, POSTED_WRITE_BITS=>POSTED_BITS) port map(
        PMEMCKE=>cke, PMEMCS_N=>cs, PMEMRAS_N=>ras, PMEMCAS_N=>cas,
        PMEMWE_N=>we, PMEMUDQ=>udq, PMEMLDQ=>ldq, PMEMBA1=>ba1,
        PMEMBA0=>ba0, PMEMADR=>ma, PMEMDAT=>dq,
        CPUBNK=>bank, CPUADR=>address, CPURDAT0=>rd0, CPURDAT1=>rd1,
        CPURDAT2=>rd2, CPURDAT3=>rd3, CPUWDAT0=>wdat, CPUWDAT1=>x"0000",
        CPUWDAT2=>x"0000", CPUWDAT3=>x"0000", CPUPRESERVE=>x"0000",
        CPUWR1=>mwr, CPUWR4=>'0', CPURD1=>'0', CPURD4=>buf_rd4, CPURMW1=>'0', CPURMW4=>'0',
        CPUBSEL=>bytes, CPUPSEL=>"0001", CPUACK=>sdr_ack, CPUCLK=>cpuclk,
        SUBBNK=>"00", SUBADR=>(others=>'0'), SUBRDAT0=>open, SUBRDAT1=>open,
        SUBRDAT2=>open, SUBRDAT3=>open, SUBWDAT0=>x"0000", SUBWDAT1=>x"0000",
        SUBWDAT2=>x"0000", SUBWDAT3=>x"0000",
        SUBWR1=>'0', SUBWR4=>'0', SUBRD1=>'0', SUBRD4=>'0', SUBRMW1=>'0', SUBRMW4=>'0',
        SUBBSEL=>"00", SUBPSEL=>"0000", SUBACK=>open, SUBCLK=>cpuclk,
        VIDBNK=>"11", VIDADR=>vid_adr, VIDDAT0=>open, VIDDAT1=>open,
        VIDDAT2=>open, VIDDAT3=>open, VIDRD=>vid_rd, VIDACK=>vid_ack, VIDCLK=>pixclk,
        FDERDAT=>open, FDEWAIT=>open, FDECLK=>cpuclk,
        FECRDAT=>open, FECWAIT=>open, FECCLK=>cpuclk,
        mem_inidone=>ready, memclk=>memclk, rstn=>rstn
    );

    lb : entity work.mainram_linebuf generic map(AW=>AW) port map(
        elig=>'1', mrd=>mrd, bank=>bank, addr=>address,
        snoop_wr=>mwr and SNOOP_ON, snoop_bank=>bank, snoop_addr=>address, flush=>'0',
        sdr_ack=>sdr_ack, sdr_rdat0=>rd0, sdr_rdat1=>rd1, sdr_rdat2=>rd2, sdr_rdat3=>rd3,
        rd4=>buf_rd4, ack=>buf_ack, doe=>buf_doe, rdat=>buf_rdat, dw=>buf_dw, rdat_hi=>buf_rdath,
        clk=>cpuclk, rstn=>rstn);
    cpu_ack <= sdr_ack or buf_ack;
    cpu_rdat <= buf_rdat when buf_doe='1' else x"dead";

    -- Font renderer: four-word video reads in bank 3 at the pixel clock,
    -- request until ACK, then a short random pause.
    video_traffic : if VIDEO generate
        process
            variable v : natural := 77;
        begin
            wait until ready='1';
            loop
                wait until rising_edge(pixclk);
                v := (v * 25173 + 13849) mod 65536;
                vid_adr <= std_logic_vector(to_unsigned(v * 4, AW));
                vid_rd <= '1';
                loop wait until rising_edge(pixclk); exit when vid_ack='1'; end loop;
                vid_rd <= '0';
                for n in 0 to (v / 256) mod 24 loop wait until rising_edge(pixclk); end loop;
            end loop;
        end process;
    end generate;

    -- Behavioural SDRAM: open row per bank, masked single-word writes; a read
    -- returns four consecutive columns (CL2), of which ST_READ uses the first.
    process
        type rows_t is array(0 to 3) of std_logic_vector(12 downto 0);
        variable open_row : rows_t := (others=>(others=>'0'));
        variable b : natural range 0 to 3;
        variable slot : integer;
        variable word : std_logic_vector(15 downto 0);
        variable w : mem_t(0 to 3);
        variable col : unsigned(9 downto 0);
    begin
        wait until falling_edge(memclk);
        if rstn='1' and ready='1' and cs='0' then
            b := to_integer(unsigned(std_logic_vector'(ba1 & ba0)));
            if ras='0' and cas='1' and we='1' then
                open_row(b) := ma;                         -- ACTIVATE
            elsif ras='1' and cas='0' then
                if we='0' then                              -- WRITE
                    slot := slot_of(ba1 & ba0, open_row(b), ma(9 downto 0));
                    assert slot>=0 report "SDRAM write outside the test set" severity failure;
                    word := sdram_words(slot);
                    if ldq='0' then word(7 downto 0) := dq(7 downto 0); end if;
                    if udq='0' then word(15 downto 8) := dq(15 downto 8); end if;
                    sdram_words(slot) <= word;
                else                                        -- READ (burst of 4)
                    for k in 0 to 3 loop
                        col := unsigned(ma(9 downto 0)) + k;
                        slot := slot_of(ba1 & ba0, open_row(b), std_logic_vector(col));
                        if slot>=0 then w(k) := sdram_words(slot); else w(k) := x"bad0"; end if;
                    end loop;
                    slot := slot_of(ba1 & ba0, open_row(b), ma(9 downto 0));
                    assert slot>=0 or b=3 report "SDRAM read outside the test set" severity failure;
                    read_source <= w(0) after 20 ns, w(1) after 30 ns, w(2) after 40 ns,
                                   w(3) after 50 ns, (others=>'Z') after 60 ns;
                end if;
            end if;
        end if;
    end process;

    process
        variable model : mem_t(0 to 4*SLOTS-1) := (others=>x"0000");
        variable s : natural := SEED;
        variable i, b, key, kind : natural;
        variable sel : std_logic_vector(1 downto 0);
        variable value, got : std_logic_vector(15 downto 0);
        variable reads, writes, hits, dwords : natural := 0;
        variable dwv : std_logic;
        variable hiv : std_logic_vector(15 downto 0);
        impure function rnd(n : positive) return natural is
        begin
            s := (s * 25173 + 13849) mod 65536;
            return (s / 16) mod n;
        end function;
        -- One bus transfer, called just after a rising edge (bridge TRANSFER).
        -- idle: clocks in IDLE after RELEASE (0 = next half of a dword).
        procedure xfer(w : std_logic; k : natural; bs : std_logic_vector(1 downto 0);
                       d : std_logic_vector(15 downto 0); idle : natural;
                       r : out std_logic_vector(15 downto 0)) is
        begin
            address <= slot_address(k mod SLOTS);
            bank <= std_logic_vector(to_unsigned(k / SLOTS, 2));
            bytes <= bs; wdat <= d;
            if w='1' then mwr<='1'; else mrd<='1'; end if;
            loop
                wait until rising_edge(cpuclk);
                exit when cpu_ack='1';
            end loop;
            r := cpu_rdat;                                 -- sampled on the ACK edge
            dwv := buf_dw and not w; hiv := buf_rdath;     -- bus_dword_capable, bus_read_high
            mwr<='0'; mrd<='0';
            loop                                           -- RELEASE
                wait until rising_edge(cpuclk);
                exit when cpu_ack='0';
            end loop;
            for n in 1 to idle loop wait until rising_edge(cpuclk); end loop;
        end procedure;
        procedure do_write(k : natural; idle : natural) is
            variable dummy : std_logic_vector(15 downto 0);
        begin
            case rnd(3) is
                when 0 => sel := "01";
                when 1 => sel := "10";
                when others => sel := "11";
            end case;
            value := std_logic_vector(to_unsigned(rnd(65536), 16));
            if sel(0)='1' then model(k)(7 downto 0) := value(7 downto 0); end if;
            if sel(1)='1' then model(k)(15 downto 8) := value(15 downto 8); end if;
            xfer('1', k, sel, value, idle, dummy);
            writes := writes + 1;
        end procedure;
        procedure do_read(k : natural; idle : natural) is
        begin
            xfer('0', k, "11", x"0000", idle, got);
            assert got = model(k)
                report "read word " & integer'image(k) & " got " & to_hstring(got) &
                    " expected " & to_hstring(model(k)) & " after " & integer'image(reads) &
                    " reads at " & integer'image(now / 1 ns) & " ns" severity failure;
            reads := reads + 1;
        end procedure;
    begin
        wait for 137 ns; rstn<='1';
        wait until ready='1';
        wait for 300 ns;
        wait until rising_edge(cpuclk);
        for op in 0 to OPS-1 loop
            b := rnd(2); i := rnd(SLOTS); key := b*SLOTS + i;
            kind := rnd(10);
            if kind < 3 then
                do_write(key, 1 + rnd(3));
            elsif kind < 6 then
                do_read(key, 1 + rnd(3));
            elsif kind < 8 then                            -- RMW: read then write
                do_read(key, 1);
                do_write(key, 1 + rnd(2));
            elsif kind < 9 then                            -- dword read
                if i mod 2 = 0 then                        -- aligned: one transfer if dw
                    do_read(key, 0);
                    if dwv='1' then
                        assert hiv = model(key+1)
                            report "dword high word " & integer'image(key+1) & " got " &
                                to_hstring(hiv) & " expected " & to_hstring(model(key+1)) &
                                " at " & integer'image(now / 1 ns) & " ns" severity failure;
                        dwords := dwords + 1;
                        wait until rising_edge(cpuclk);
                    else
                        do_read(key+1, 1 + rnd(2));
                    end if;
                elsif i mod 4 /= 3 then                    -- misaligned: two halves
                    do_read(key, 0); do_read(key+1, 1 + rnd(2));
                else
                    do_read(key, 1);
                end if;
            else                                           -- dword write
                if i mod 4 /= 3 then
                    do_write(key, 0); do_write(key+1, 1 + rnd(2));
                else
                    do_write(key, 1);
                end if;
            end if;
        end loop;
        for k in 0 to 2*SLOTS-1 loop
            do_read(k, 1);
        end loop;
        assert dwords > 0 report "no single-transfer dword reads" severity failure;
        report "PASS line buffer + SDRAMC: " & integer'image(writes) & " writes, " &
            integer'image(reads) & " reads (" & integer'image(dwords) & " dwords in one transfer), CPU " & integer'image(CPU_MHZ) & " MHz, phase " &
            integer'image(MEM_PHASE_PS) & " ps" &
            ", " & integer'image(now / 1 ns) & " ns" severity note;
        stop;
        wait;
    end process;
end architecture;
