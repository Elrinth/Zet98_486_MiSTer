-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use work.mem_addr_pkg.all;
use std.env.all;
entity cache_map_tb is end;
architecture test of cache_map_tb is
    signal cpuaddr : std_logic_vector(19 downto 1) := (others=>'0');
    signal BNK89_SEL, BNKAB_SEL : std_logic_vector(7 downto 0) := x"08";
    signal tga, stb, cpuoe, DMAen : std_logic := '0';
    signal LDR_OE : std_logic := '0';
    signal MADDR, CB_ADDR : std_logic_vector(21 downto 0);
    signal MWR, MSD_CS, cache_invalidate, reference_invalidate : std_logic;
    signal itfen, biosen, sounden, vsel, emsen, necemsen : std_logic := '1';
    signal dmaaddr : std_logic_vector(19 downto 1) := (others=>'0');
begin
    mapper: entity work.memorymap generic map(SDAWIDTH=>22) port map(
        CPUADDR=>cpuaddr, CPUSEL=>"11", CPUTGA=>tga, CPUSTB=>stb, CPUOE=>cpuoe,
        DMAEN=>DMAen, DMAADDR=>dmaaddr, DMARD=>'0', DMAWR=>'0',
        BNK89SEL=>BNK89_SEL, BNKABSEL=>BNKAB_SEL, SDR_CS=>MSD_CS, SDR_BANK=>open, SDR_ADDR=>MADDR,
        GRAM_CS=>open, TRAM_CS=>open, TRAM_ADDR=>open, ARAM_CS=>open, ARAM_ADDR=>open,
        NVRAM_CS=>open, NVRAM_ADDR=>open, DBIOS_CS=>open, DBIOS_ADDR=>open,
        ITFEN=>itfen, BIOSEN=>biosen, SOUNDEN=>sounden, VSEL=>vsel, EMSEN=>emsen, NECEMSEN=>necemsen,
        EMSA0=>x"00", EMSA1=>x"00", EMSA2=>x"00", EMSA3=>x"00",
        MRD=>open, MWR=>MWR, clk=>'0', rstn=>'1');
    -- Independent reference: the original complete memory-map predicate.
    CB_ADDR <= RAM_BIOS(21 downto 0) when LDR_OE='1' else MADDR;
    reference_invalidate <= '1' when DMAen='1' else
        '1' when MWR='1' and MSD_CS='1' and cpuaddr(19)='1' and
                 CB_ADDR>=RAM_MAIN(21 downto 0) and
                 CB_ADDR<(RAM_MAIN(21 downto 0)+x"40000") else '0';
    process
        variable expected : std_logic;
        variable count : integer := 0;
        variable settings : std_logic_vector(5 downto 0);
    begin
        stb<='1'; cpuoe<='1'; BNKAB_SEL<=x"0a";
        for bank in 0 to 255 loop
            BNK89_SEL<=conv_std_logic_vector(bank,8); BNKAB_SEL<=conv_std_logic_vector(bank,8);
            if bank<8 then expected:='1'; else expected:='0'; end if;
            for window in 4 to 5 loop
                for offset in 0 to 1 loop
                    cpuaddr<=conv_std_logic_vector(window*65536+offset*32767,19);
                    tga<='0'; cpuoe<='1'; wait for 1 ns;
                    assert cache_invalidate=expected report "Wrong RAM alias invalidation, bank "&integer'image(bank) severity failure;
                    cpuoe<='0'; wait for 1 ns;
                    assert cache_invalidate='0' report "Read invalidated cache" severity failure;
                    tga<='1'; cpuoe<='1'; wait for 1 ns;
                    assert cache_invalidate='0' report "I/O invalidated cache" severity failure;
                    count:=count+3;
                end loop;
            end loop;
        end loop;
        tga<='0'; cpuoe<='1'; BNK89_SEL<=x"08"; BNKAB_SEL<=x"0a";
        for addr in 0 to 1048575 loop
            if addr mod 4096=0 then
                cpuaddr<=conv_std_logic_vector(addr/2,19); wait for 1 ns;
                assert cache_invalidate='0' report "Unaliased CPU write invalidated cache" severity failure;
                count:=count+1;
            end if;
        end loop;
        stb<='0'; DMAen<='1'; wait for 1 ns;
        assert cache_invalidate='1' report "DMA ownership failed to invalidate" severity failure;
        DMAen<='0'; wait for 1 ns;
        assert cache_invalidate='0' report "DMA release failed" severity failure;
        -- Compare against the actual mapper for every bank, 4 KB boundary
        -- and independent ROM/EMS/display setting combination. Low address
        -- bits cannot affect a target below 80000h; both ends were checked above.
        stb<='1'; cpuoe<='1'; tga<='0';
        for mode in 0 to 63 loop
            settings:=conv_std_logic_vector(mode,6);
            itfen<=settings(0); biosen<=settings(1); sounden<=settings(2);
            vsel<=settings(3); emsen<=settings(4); necemsen<=settings(5);
            for bank in 0 to 255 loop
                BNK89_SEL<=conv_std_logic_vector(bank,8);
                BNKAB_SEL<=conv_std_logic_vector(255-bank,8);
                for page in 0 to 255 loop
                    cpuaddr<=conv_std_logic_vector(page*2048,19);
                    wait for 1 ns;
                    assert cache_invalidate=reference_invalidate
                        report "Direct bank decode differs from complete memory map" severity failure;
                    count:=count+1;
                end loop;
            end loop;
        end loop;
        -- Loader accesses bypass the CPU map. DMA always wins, irrespective
        -- of address, write/read direction or loader state.
        BNK89_SEL<=x"00"; BNKAB_SEL<=x"00"; cpuaddr<=conv_std_logic_vector(16#40000#,19);
        LDR_OE<='1'; wait for 1 ns;
        assert cache_invalidate='0' report "Loader invalidated cache" severity failure;
        for page in 0 to 255 loop
            DMAen<='1'; dmaaddr<=conv_std_logic_vector(page*2048,19); wait for 1 ns;
            assert cache_invalidate='1' report "DMA address affected invalidation" severity failure;
        end loop;
        report "PASS: cache mapping: "&integer'image(count)&" bank/read/write/I/O cases plus DMA ownership";
        stop;
        wait;
    end process;
end architecture;
