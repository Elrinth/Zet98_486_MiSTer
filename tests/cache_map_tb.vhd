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
    signal b89, bab : std_logic_vector(7 downto 0) := x"08";
    signal tga, stb, oe, DMAen : std_logic := '0';
    signal CB_ADDR : std_logic_vector(21 downto 0);
    signal MWR, MSD_CS, cache_invalidate : std_logic;
begin
    mapper: entity work.memorymap generic map(SDAWIDTH=>22) port map(
        CPUADDR=>cpuaddr, CPUSEL=>"11", CPUTGA=>tga, CPUSTB=>stb, CPUOE=>oe,
        DMAEN=>DMAen, DMAADDR=>(others=>'0'), DMARD=>'0', DMAWR=>'0',
        BNK89SEL=>b89, BNKABSEL=>bab, SDR_CS=>MSD_CS, SDR_BANK=>open, SDR_ADDR=>CB_ADDR,
        GRAM_CS=>open, TRAM_CS=>open, TRAM_ADDR=>open, ARAM_CS=>open, ARAM_ADDR=>open,
        NVRAM_CS=>open, NVRAM_ADDR=>open, DBIOS_CS=>open, DBIOS_ADDR=>open,
        ITFEN=>'1', BIOSEN=>'1', SOUNDEN=>'1', VSEL=>'0', EMSEN=>'1', NECEMSEN=>'1',
        EMSA0=>x"00", EMSA1=>x"00", EMSA2=>x"00", EMSA3=>x"00",
        MRD=>open, MWR=>MWR, clk=>'0', rstn=>'1');
    process
        variable expected : std_logic;
        variable count : integer := 0;
    begin
        stb<='1'; oe<='1'; bab<=x"0a";
        for bank in 0 to 255 loop
            b89<=conv_std_logic_vector(bank,8); bab<=conv_std_logic_vector(bank,8);
            if bank<8 then expected:='1'; else expected:='0'; end if;
            for window in 4 to 5 loop
                for offset in 0 to 1 loop
                    cpuaddr<=conv_std_logic_vector(window*65536+offset*32767,19);
                    tga<='0'; oe<='1'; wait for 1 ns;
                    assert cache_invalidate=expected report "Wrong RAM alias invalidation, bank "&integer'image(bank) severity failure;
                    oe<='0'; wait for 1 ns;
                    assert cache_invalidate='0' report "Read invalidated cache" severity failure;
                    tga<='1'; oe<='1'; wait for 1 ns;
                    assert cache_invalidate='0' report "I/O invalidated cache" severity failure;
                    count:=count+3;
                end loop;
            end loop;
        end loop;
        tga<='0'; oe<='1'; b89<=x"08"; bab<=x"0a";
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
        report "PASS: cache mapping: "&integer'image(count)&" bank/read/write/I/O cases plus DMA ownership";
        stop;
        wait;
    end process;
end architecture;
