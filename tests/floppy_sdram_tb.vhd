library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Check physical SDRAM pins and WAIT/data on both floppy buffer ports.
entity floppy_sdram_tb is
    generic (CPU_MHZ : positive := 50; BUFFERED : boolean := true;
             MEM_PHASE_PS : natural := 0; USE_FEC : boolean := false);
end entity;
architecture test of floppy_sdram_tb is
    constant AW : positive := 22;
    signal cpuclk, memclk, rstn, ready : std_logic := '0';
    signal address : std_logic_vector(AW-1 downto 0) := (others=>'0');
    signal bank, bytes : std_logic_vector(1 downto 0) := "00";
    signal planes : std_logic_vector(3 downto 0) := "0000";
    type words_t is array(0 to 3) of std_logic_vector(15 downto 0);
    signal wd : words_t := (others=>x"0000");
    signal preserve_mask : std_logic_vector(15 downto 0) := x"0000";
    signal address_all, expected_address : std_logic_vector(AW+1 downto 0) := (others=>'0');
    signal fde_rd, fde_wr, fec_rd, fec_wr, read_req, write_req : std_logic := '0';
    signal fde_wait, fec_wait, busy : std_logic;
    signal fde_data, fec_data, returned_data : std_logic_vector(15 downto 0);
    signal expected_data : std_logic_vector(15 downto 0);
    signal reading, active : boolean := false;
    signal cke, cs, ras, cas, we, udq, ldq, ba1, ba0 : std_logic;
    signal ma : std_logic_vector(12 downto 0);
    signal dq, read_source : std_logic_vector(15 downto 0) := (others=>'Z');
    signal activations, commands : natural := 0;
begin
    cpuclk <= not cpuclk after 500 ns / CPU_MHZ;
    process begin
        wait for MEM_PHASE_PS * 1 ps;
        loop wait for 5 ns; memclk<=not memclk; end loop;
    end process;
    fde_rd <= read_req when not USE_FEC else '0';
    fde_wr <= write_req when not USE_FEC else '0';
    fec_rd <= read_req when USE_FEC else '0';
    fec_wr <= write_req when USE_FEC else '0';
    busy <= fec_wait when USE_FEC else fde_wait;
    returned_data <= fec_data when USE_FEC else fde_data;
    dq <= read_source;
    dut : entity work.SDRAMC generic map(AW,100,64000/8192,false,false,BUFFERED) port map(
        PMEMCKE=>cke, PMEMCS_N=>cs, PMEMRAS_N=>ras, PMEMCAS_N=>cas,
        PMEMWE_N=>we, PMEMUDQ=>udq, PMEMLDQ=>ldq, PMEMBA1=>ba1,
        PMEMBA0=>ba0, PMEMADR=>ma, PMEMDAT=>dq,
        CPUBNK=>bank, CPUADR=>address, CPURDAT0=>open, CPURDAT1=>open,
        CPURDAT2=>open, CPURDAT3=>open, CPUWDAT0=>wd(0), CPUWDAT1=>wd(1),
        CPUWDAT2=>wd(2), CPUWDAT3=>wd(3), CPUPRESERVE=>preserve_mask,
        CPUWR1=>'0', CPUWR4=>'0',
        CPURD1=>'0', CPURD4=>'0', CPURMW1=>'0', CPURMW4=>'0',
        CPUBSEL=>bytes, CPUPSEL=>planes, CPUACK=>open, CPUCLK=>cpuclk,
        SUBBNK=>bank, SUBADR=>address, SUBRDAT0=>open, SUBRDAT1=>open,
        SUBRDAT2=>open, SUBRDAT3=>open, SUBWDAT0=>wd(0), SUBWDAT1=>wd(1),
        SUBWDAT2=>wd(2), SUBWDAT3=>wd(3), SUBPRESERVE=>preserve_mask,
        SUBWR1=>'0', SUBWR4=>'0', SUBRD1=>'0', SUBRD4=>'0',
        SUBRMW1=>'0', SUBRMW4=>'0', SUBBSEL=>bytes,
        SUBPSEL=>planes, SUBACK=>open, SUBCLK=>cpuclk,
        VIDBNK=>"00", VIDADR=>(others=>'0'), VIDDAT0=>open, VIDDAT1=>open,
        VIDDAT2=>open, VIDDAT3=>open, VIDRD=>'0', VIDACK=>open, VIDCLK=>cpuclk,
        FDEADR=>address_all, FDEWDAT=>wd(0), FDERD=>fde_rd, FDEWR=>fde_wr,
        FDERDAT=>fde_data, FDEWAIT=>fde_wait, FDECLK=>cpuclk,
        FECADR=>address_all, FECWDAT=>wd(0), FECRD=>fec_rd, FECWR=>fec_wr,
        FECRDAT=>fec_data, FECWAIT=>fec_wait, FECCLK=>cpuclk,
        mem_inidone=>ready, memclk=>memclk, rstn=>rstn
    );

    process begin
        wait until falling_edge(memclk);
        if rstn='1' and ready='1' then
            if cs='0' and ras='0' and cas='1' and we='1' then
                assert active report "unsolicited floppy SDRAM activation" severity failure;
                assert ma=expected_address(AW-1 downto AW-13) and
                       (ba1 & ba0)=expected_address(AW+1 downto AW)
                    report "floppy SDRAM row/bank mismatch" severity failure;
                activations<=activations+1;
            end if;
            if cs='0' and ras='1' and cas='0' then
                assert active report "unsolicited floppy SDRAM command" severity failure;
                assert ma(9 downto 0)=expected_address(9 downto 0) and
                       (ba1 & ba0)=expected_address(AW+1 downto AW)
                    report "floppy SDRAM column/bank mismatch" severity failure;
                assert (udq & ldq)=std_logic_vector'("00") report "floppy byte mask mismatch" severity failure;
                assert (reading and we='1') or (not reading and we='0') report "floppy command mismatch" severity failure;
                commands<=commands+1;
                if reading then
                    read_source<=expected_data after 20 ns, (others=>'Z') after 30 ns;
                else
                    assert dq=expected_data report "floppy SDRAM write data mismatch" severity failure;
                end if;
            end if;
        end if;
    end process;
    process
        variable a, c : natural;
    begin
        wait for 137 ns; rstn<='1'; wait until ready='1'; wait for 300 ns;
        for n in 0 to 255 loop
            wait until falling_edge(cpuclk);
            address_all<=std_logic_vector(to_unsigned((n*130071+911) mod 2**(AW+2),AW+2));
            expected_address<=std_logic_vector(to_unsigned((n*130071+911) mod 2**(AW+2),AW+2));
            wd(0)<=std_logic_vector(to_unsigned((n*8191+349) mod 65536,16));
            expected_data<=std_logic_vector(to_unsigned((n*8191+349) mod 65536,16));
            reading<=n mod 2=0; active<=true; a:=activations; c:=commands;
            if n mod 2=0 then read_req<='1'; else write_req<='1'; end if;
            wait until busy='1' for 1 us;
            assert busy='1' report "floppy request not accepted" severity failure;
            -- After acceptance a buffered request no longer reads live pins.
            if BUFFERED then
                wait until falling_edge(cpuclk);
                read_req<='0'; write_req<='0';
                address_all<=not expected_address; wd(0)<=not expected_data;
            end if;
            wait until busy='0' for 3 us;
            assert busy='0' report "floppy request timed out" severity failure;
            wait for 1 ps;
            assert activations=a+1 and commands=c+1 report "duplicated/missing floppy command" severity failure;
            if n mod 2=0 then
                assert returned_data=expected_data report "floppy read data missing on WAIT completion" severity failure;
            end if;
            wait until falling_edge(cpuclk);
            read_req<='0'; write_req<='0'; active<=false;
            wait until falling_edge(cpuclk);
        end loop;
        report "PASS: 256 floppy requests, FEC=" & boolean'image(USE_FEC) &
            " buffered=" & boolean'image(BUFFERED) & " MHz=" & integer'image(CPU_MHZ);
        finish;
    end process;
    process begin wait for 3 ms; assert false report "floppy SDRAM watchdog" severity failure; end process;
end architecture;
