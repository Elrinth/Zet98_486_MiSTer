library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.mem_addr_pkg.all;

entity bios_shadow_tb is end;
architecture test of bios_shadow_tb is
    signal addr : std_logic_vector(19 downto 1) := (others=>'0');
    signal bank89 : std_logic_vector(7 downto 0) := x"0e";
    signal wr, itf, dma : std_logic := '0';
    signal bios : std_logic := '1';
    signal ramaddr : std_logic_vector(21 downto 0);
    signal rambank : std_logic_vector(1 downto 0);
    signal physical : unsigned(23 downto 0);
begin
    physical <= unsigned(rambank & ramaddr);
    dut: entity work.memorymap generic map(SDAWIDTH=>22) port map(
        CPUADDR=>addr, CPUSEL=>"11", CPUTGA=>'0', CPUSTB=>'1', CPUOE=>wr,
        DMAEN=>dma, DMAADDR=>addr, DMARD=>'0', DMAWR=>wr,
        BNK89SEL=>bank89, BNKABSEL=>x"0e",
        SDR_CS=>open, SDR_BANK=>rambank, SDR_ADDR=>ramaddr,
        GRAM_CS=>open, TRAM_CS=>open, TRAM_ADDR=>open,
        ARAM_CS=>open, ARAM_ADDR=>open, NVRAM_CS=>open, NVRAM_ADDR=>open,
        CGWIN_CS=>open, DBIOS_CS=>open, DBIOS_ADDR=>open, UMA_OPEN=>open,
        SND_STUB=>open, SND_STUB_WORD=>open,
        ITFEN=>itf, BIOSEN=>bios, SOUNDEN=>'0', VSEL=>'0',
        EMSEN=>'0', NECEMSEN=>'0', EMSA0=>x"00", EMSA1=>x"00",
        EMSA2=>x"00", EMSA3=>x"00", MRD=>open, MWR=>open,
        clk=>'0', rstn=>'1');
    process
        procedure address(a : natural; writing : std_logic) is
        begin
            addr <= std_logic_vector(to_unsigned(a/2, 19)); wr <= writing;
            wait for 1 ns;
        end;
        variable rom_word, shadow_word : natural;
    begin
        -- Model the actual POST copy E800:0000 -> 8800:0000 with bank 0Eh,
        -- then the readback after switching 053Dh to RAM. Test both windows.
        for offset in 0 to 16#bfff# loop
            rom_word := to_integer(unsigned(RAM_BIOS)) + offset;
            shadow_word := to_integer(unsigned(RAM_MAIN)) + 16#e8000#/2 + offset;
            address(16#e8000#+offset*2, '0');
            assert physical=rom_word report "ROM source mapping" severity failure;
            address(16#88000#+offset*2, '1');
            assert physical=shadow_word report "Banked copy missed shadow RAM" severity failure;
            address(16#a8000#+offset*2, '1');
            assert physical=shadow_word report "Second window missed shadow RAM" severity failure;
            bios <= '0'; address(16#e8000#+offset*2, '0');
            assert physical=shadow_word report "Shadow readback differs from copy destination" severity failure;
            bios <= '1';
        end loop;
        -- ITF reads retain their bank; copying through a window still targets RAM.
        itf <= '1'; address(16#98000#, '0');
        assert physical=unsigned(RAM_ITF) report "ITF read mapping" severity failure;
        address(16#98000#, '1');
        assert physical=to_integer(unsigned(RAM_MAIN))+16#f8000#/2
            report "ITF window write missed shadow RAM" severity failure;
        itf <= '0'; bank89 <= x"08"; address(16#88000#, '1');
        assert physical=to_integer(unsigned(RAM_MAIN))+16#88000#/2
            report "Native RAM write changed" severity failure;
        report "BIOS shadow copy/readback PASS (entire 96 KiB, both windows)";
        stop; wait;
    end process;
end;
