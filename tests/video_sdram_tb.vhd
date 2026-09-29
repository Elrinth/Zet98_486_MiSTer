library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package video_capture is
    type capture_t is protected
        procedure write_word(data : std_logic_vector(15 downto 0); address : natural);
        procedure expect_page(index : natural; page : std_logic);
        procedure check_lines(lines : natural);
    end protected;
    shared variable capture : capture_t;
end package;
package body video_capture is
    type capture_t is protected body
    type counts_t is array(0 to 3) of natural;
    variable capture_counts : counts_t := (others=>0);
    type pages_t is array(0 to 639) of std_logic;
    variable pages : pages_t := (others=>'X');
    procedure expect_page(index : natural; page : std_logic) is
    begin pages(index):=page; end procedure;
    procedure write_word(data : std_logic_vector(15 downto 0); address : natural) is
        variable plane, word : natural;
    begin
        assert not is_x(data) report "Unknown graphics plane data" severity failure;
        plane:=to_integer(unsigned(data(15 downto 14)));
        word:=to_integer(unsigned(data(12 downto 0)));
        assert data(13)=pages(word) report "Graphics plane from wrong display page" severity failure;
        assert word=capture_counts(plane) and address=word mod 40
            report "Missing, duplicate or reordered graphics word: plane=" &
                integer'image(plane) & " word=" & integer'image(word) &
                " expected=" & integer'image(capture_counts(plane)) severity failure;
        capture_counts(plane):=capture_counts(plane)+1;
    end procedure;
    procedure check_lines(lines : natural) is
    begin
        for plane in 0 to 3 loop
            assert capture_counts(plane)=40*lines report "Incomplete graphics line buffers" severity failure;
        end loop;
    end procedure;
    end protected body;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.video_capture.all;

-- Behavioral replacement for the Intel line RAM, with checks on its actual
-- write-enable and input pins. The controller and graphics reader are real.
entity graphbuf816 is
    port(clock : in std_logic; data : in std_logic_vector(15 downto 0);
         rdaddress : in std_logic_vector(6 downto 0);
         wraddress : in std_logic_vector(5 downto 0); wren : in std_logic;
         q : out std_logic_vector(7 downto 0));
end entity;
architecture test of graphbuf816 is
    type ram_t is array(0 to 63) of std_logic_vector(15 downto 0);
    signal ram : ram_t := (others=>(others=>'0'));
begin
    process(clock) begin
        if rising_edge(clock) then
            if wren='1' then
                assert data'last_event >= 20 ns
                    report "Graphics data changed too close to enabled RAM capture" severity failure;
                capture.write_word(data,to_integer(unsigned(wraddress)));
                ram(to_integer(unsigned(wraddress)))<=data;
            end if;
            if rdaddress(0)='0' then
                q<=ram(to_integer(unsigned(rdaddress(6 downto 1))))(7 downto 0);
            else
                q<=ram(to_integer(unsigned(rdaddress(6 downto 1))))(15 downto 8);
            end if;
        end if;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.video_capture.all;
use work.VIDEO_TIMING_pkg.all;

entity video_sdram_tb is
    generic(PHASE_PS : natural := 0; DATA_DELAY_NS : natural := 20; ADDRESS_DELAY_NS : natural := 20;
            CPU_MHZ : positive := 50; HOLD_GLITCH : boolean := false);
end entity;
architecture test of video_sdram_tb is
    signal memclk, pixelclk, cpuclk, rstn, ready : std_logic := '0';
    signal cpu_read, cpu_ack : std_logic := '0';
    signal cpu_commands : natural := 0;
    signal cke, cs, ras, cas, we, udq, ldq, ba1, ba0 : std_logic;
    signal ma : std_logic_vector(12 downto 0);
    signal dq : std_logic_vector(15 downto 0) := (others=>'Z');
    signal ga : std_logic_vector(13 downto 0);
    signal va : std_logic_vector(21 downto 0);
    signal delayed_ga : std_logic_vector(13 downto 0);
    signal cpu_page : std_logic := '1';
    -- Two CDC stages, SDRAMC.MEMADR, then the physical PMEMADR register.
    signal page_history : std_logic_vector(3 downto 0) := "0000";
    signal front_reads, back_reads : natural := 0;
    signal rd, ack : std_logic;
    type words_t is array(0 to 3) of std_logic_vector(15 downto 0);
    signal data, routed_data, delayed_data : words_t;
    signal hold_poison : std_logic := '0';
    signal hold_checks : natural := 0;
    signal uc : natural range 0 to 7 := 0;
    signal hc : natural range 0 to 99 := 0;
    signal vc : natural range 0 to 524 := VIV;
    signal commands : natural := 0;
begin
    memclk<=not memclk after 5 ns;
    cpuclk<=not cpuclk after (500000 / CPU_MHZ) * 1 ps;
    process begin
        wait until ready='1';
        loop
            for edge in 1 to 37 loop wait until rising_edge(cpuclk); end loop;
            cpu_page<=not cpu_page;
        end loop;
    end process;
    process(memclk) begin
        if rising_edge(memclk) then page_history<=page_history(2 downto 0) & cpu_page; end if;
    end process;
    process begin
        wait for PHASE_PS * 1 ps;
        loop pixelclk<='1'; wait for 20 ns; pixelclk<='0'; wait for 20 ns; end loop;
    end process;
    delays : for lane in 0 to 3 generate
        routed_data(lane)<=transport data(lane) after DATA_DELAY_NS * 1 ns;
        delayed_data(lane)<=routed_data(lane) xor x"0001" when HOLD_GLITCH and hold_poison='1'
                            else routed_data(lane);
    end generate;
    -- RD and ACK are high at exactly the enabled BS_READ -> WDAT capture.
    -- Check the next 20 ns as well as the pre-capture check in the runner.
    -- Inspect producer and routed data, including a zero-delay route. The
    -- protocol cannot reuse VIDDAT until a fresh request crosses back to
    -- SDRAMC and a new SDRAM read completes.
    process begin
        wait until rising_edge(pixelclk);
        if rstn='1' and rd='1' and ack='1' then
            hold_poison<='1' after 1 ns, '0' after 5 ns;
            wait for 20 ns;
            assert data'stable(20 ns) and delayed_data'stable(20 ns)
                report "Graphics data changed after enabled WDAT capture" severity failure;
            hold_checks<=hold_checks+1;
        end if;
    end process;
    delayed_ga <= transport ga after ADDRESS_DELAY_NS * 1 ns;
    display_address : entity work.display_page_address
        port map(memory_clk=>memclk, async_rstn=>rstn, cpu_page=>cpu_page,
                 pixel_address=>delayed_ga, memory_address=>va);
    memory : entity work.SDRAMC generic map(22,100,64000/8192) port map(
        PMEMCKE=>cke, PMEMCS_N=>cs, PMEMRAS_N=>ras, PMEMCAS_N=>cas,
        PMEMWE_N=>we, PMEMUDQ=>udq, PMEMLDQ=>ldq, PMEMBA1=>ba1,
        PMEMBA0=>ba0, PMEMADR=>ma, PMEMDAT=>dq,
        CPUBNK=>"01", CPUADR=>(others=>'0'), CPURDAT0=>open, CPURDAT1=>open,
        CPURDAT2=>open, CPURDAT3=>open, CPUWDAT0=>x"0000", CPUWDAT1=>x"0000",
        CPUWDAT2=>x"0000", CPUWDAT3=>x"0000", CPUWR1=>'0', CPUWR4=>'0',
        CPURD1=>cpu_read, CPURD4=>'0', CPURMW1=>'0', CPURMW4=>'0',
        CPUBSEL=>"00", CPUPSEL=>"0000", CPUACK=>cpu_ack, CPUCLK=>cpuclk,
        SUBBNK=>"00", SUBADR=>(others=>'0'), SUBRDAT0=>open, SUBRDAT1=>open,
        SUBRDAT2=>open, SUBRDAT3=>open, SUBWDAT0=>x"0000", SUBWDAT1=>x"0000",
        SUBWDAT2=>x"0000", SUBWDAT3=>x"0000", SUBWR1=>'0', SUBWR4=>'0',
        SUBRD1=>'0', SUBRD4=>'0', SUBRMW1=>'0', SUBRMW4=>'0', SUBBSEL=>"00",
        SUBPSEL=>"0000", SUBACK=>open, SUBCLK=>pixelclk,
        VIDBNK=>"00", VIDADR=>va, VIDDAT0=>data(0),
        VIDDAT1=>data(1), VIDDAT2=>data(2), VIDDAT3=>data(3),
        VIDRD=>rd, VIDACK=>ack, VIDCLK=>pixelclk,
        FDERDAT=>open, FDEWAIT=>open, FDECLK=>pixelclk,
        FECRDAT=>open, FECWAIT=>open, FECCLK=>pixelclk,
        mem_inidone=>ready, memclk=>memclk, rstn=>rstn);
    graphics : entity work.GRAPHSCR98 port map(
        GRAMADR=>ga, GRAMRD=>rd, GRAMACK=>ack,
        GRAMDAT0=>delayed_data(0), GRAMDAT1=>delayed_data(1),
        GRAMDAT2=>delayed_data(2), GRAMDAT3=>delayed_data(3), DOTOUT=>open, DOTE=>open,
        GRAPHEN=>'1', DOTPLINE=>"00000", BLANK=>'0', UCOUNT=>uc, HUCOUNT=>hc,
        VCOUNT=>vc, HCOMP=>'0', VCOMP=>'0', BASEADDR0=>(others=>'0'),
        BASEADDR1=>(others=>'0'), LINENUM0=>"0111111111",
        LINENUM1=>(others=>'0'), BASEADDR2=>(others=>'0'), BASEADDR3=>(others=>'0'),
        LINENUM2=>(others=>'0'), LINENUM3=>(others=>'0'), PITCH=>x"28", clk=>pixelclk, rstn=>rstn);
    process
        variable row : unsigned(12 downto 0) := (others=>'0');
        variable addr : unsigned(21 downto 0);
        variable word, page : natural;
    begin
        wait until falling_edge(memclk);
        if ready='1' then
            if cs='0' and ras='0' and cas='1' and we='1' then
                row:=unsigned(ma);
                if ba0='0' then
                    assert ma(12 downto 8)="00010" and ma(7)=page_history(3)
                        report "Wrong or unsynchronized graphics display page" severity failure;
                end if;
            end if;
            if cs='0' and ras='1' and cas='0' and we='1' then
                if ba0='1' then
                    dq<=x"a55a" after 20 ns, (others=>'Z') after 30 ns;
                    cpu_commands<=cpu_commands+1;
                else
                addr:=row & unsigned(ma(8 downto 0));
                -- ADRWIDTH=22 uses nine independent column bits; bit 9 is
                -- already present in the row. Test crosses multiple rows.
                word:=to_integer(addr(15 downto 2));
                assert word=commands report "Wrong graphics SDRAM address" severity failure;
                capture.expect_page(commands,addr(16));
                if addr(16)='1' then page:=16#2000#; back_reads<=back_reads+1;
                else page:=0; front_reads<=front_reads+1; end if;
                dq<=std_logic_vector(to_unsigned(page+word,16)) after 20 ns,
                    std_logic_vector(to_unsigned(16#4000#+page+word,16)) after 30 ns,
                    std_logic_vector(to_unsigned(16#8000#+page+word,16)) after 40 ns,
                    std_logic_vector(to_unsigned(16#c000#+page+word,16)) after 50 ns,
                    (others=>'Z') after 60 ns;
                commands<=commands+1;
                end if;
            end if;
        end if;
    end process;
    process begin
        wait until ready='1';
        loop
            wait until falling_edge(cpuclk); cpu_read<='1';
            wait until cpu_ack='1';
            wait until falling_edge(cpuclk); cpu_read<='0';
            wait until cpu_ack='0';
            wait until falling_edge(cpuclk);
        end loop;
    end process;
    process begin
        wait for 137 ns;
        assert va(21 downto 16)="000100" report "Display page not reset to front" severity failure;
        for plane in 0 to 3 loop
            assert data(plane)=x"0000" report "Graphics plane not reset" severity failure;
        end loop;
        rstn<='1';
        wait until ready='1';
        -- GRAPHSCR can have queued the first line during SDRAM initialization.
        wait until ack='1';
        for line in 0 to 15 loop
            for pixel in 0 to 799 loop
                wait until falling_edge(pixelclk);
                uc<=pixel mod 8; hc<=pixel/8; vc<=VIV+line;
            end loop;
            capture.check_lines(line+1);
        end loop;
        wait until rising_edge(pixelclk);
        assert cpu_commands>100 report "CPU contention was not exercised" severity failure;
        assert commands=640 report "Incorrect graphics burst count" severity failure;
        assert hold_checks=640 report "Incomplete post-capture hold checks" severity failure;
        assert front_reads>100 and back_reads>100 report "Both display pages not exercised" severity failure;
        report "PASS: 16 four-plane graphics lines, phase=" & integer'image(PHASE_PS) &
            " ps, data route=" & integer'image(DATA_DELAY_NS) & " ns, >=20 ns setup/hold capture margins";
        finish;
    end process;
    process begin wait for 2 ms; assert false report "Graphics SDRAM watchdog" severity failure; end process;
end architecture;
