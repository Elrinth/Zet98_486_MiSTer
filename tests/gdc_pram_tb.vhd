-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Same registered read-address latency as the production gdcfifo M9K wrapper.
entity gdcfifo is
    port(clock:in std_logic;data:in std_logic_vector(8 downto 0);
         rdaddress,wraddress:in std_logic_vector(3 downto 0);
         wren:in std_logic;q:out std_logic_vector(8 downto 0));
end;
architecture model of gdcfifo is
    type ram_t is array(0 to 15) of std_logic_vector(8 downto 0);
    signal ram:ram_t:=(others=>(others=>'0'));
    signal ra:integer range 0 to 15:=0;
begin
    process(clock) begin if rising_edge(clock) then
        ra<=to_integer(unsigned(rdaddress));
        if wren='1' then ram(to_integer(unsigned(wraddress)))<=data;end if;
    end if;end process;
    q<=ram(ra);
end;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity gdc_pram_tb is
    generic (BUS_GAP:natural:=15; ACK_DELAY:natural:=2);
end;
architecture test of gdc_pram_tb is
    signal clk,rstn,cs,wr:std_logic:='0';signal done:boolean:=false;
    signal addr:std_logic_vector(1 downto 0):="00";
    signal din,dout,pitch:std_logic_vector(7 downto 0):=(others=>'0');
    signal b0,b1:std_logic_vector(17 downto 0);
    signal l0,l1,l2,l3:std_logic_vector(9 downto 0);
    signal b2,b3:std_logic_vector(13 downto 0);
    signal legacy_rows:std_logic_vector(4 downto 0);
    signal ma:std_logic_vector(17 downto 0);
    signal wd:std_logic_vector(15 downto 0);
    signal mr,mw,ack:std_logic:='0';
    signal last_word:std_logic_vector(15 downto 0);
    signal writes:natural:=0;
    signal scan_h:integer range 0 to work.VIDEO_TIMING_pkg.HUWIDTH-1:=1;
    signal scan_row:integer range 0 to work.VIDEO_TIMING_pkg.VWIDTH-1:=0;
    signal scan_address:std_logic_vector(18 downto 3);
    type bytes_t is array(0 to 15) of natural range 0 to 255;
begin
    clk<=not clk after 5 ns when not done;
    process begin
        wait for 20 ms;
        assert done report "GRAGDC PRAM test timed out" severity failure;
        wait;
    end process;
    dut:entity work.GRAGDC port map(CS=>cs,ADDR=>addr,RD=>'0',WR=>wr,DIN=>din,DOUT=>dout,DOE=>open,
        LPEND=>'0',VRTC=>'0',HRTC=>'0',VRAMSEL=>open,CRAMSEL=>open,INTR=>open,GRAPHEN=>open,VZOOM=>open,
        BASEADDR0=>b0,BASEADDR1=>b1,SL0=>l0,SL1=>l1,
        BASEADDR2=>b2,BASEADDR3=>b3,SL2=>l2,SL3=>l3,IM=>open,PITCH=>pitch,DOTPLINE=>legacy_rows,
        GDC_ADDR=>ma,GDC_RDAT=>x"0000",GDC_WDAT=>wd,GDC_RD=>mr,GDC_WR=>mw,GDC_MACK=>ack,clk=>clk,rstn=>rstn);
    -- Decoder-to-raster control: transport has its own production CDC suite.
    raster:entity work.pegc_raster port map(clk=>clk,rstn=>rstn,
        mode256=>'1',single_page=>'1',display_page=>'0',fast_clock=>'0',graph_enable=>'1',
        base0=>b0(14 downto 0),base1=>b1(14 downto 0),length0=>l0,length1=>l1,
        pitch=>pitch,repeat_lines=>legacy_rows,hunit=>scan_h,dot=>0,row=>scan_row,
        line_start=>open,line_enable=>open,active=>open,line_address=>scan_address,pixel_x=>open,mode_pixel=>open);
    -- A real request/ACK/idle handshake, with configurable memory latency.
    process(clk)
        variable ticks:natural:=0;
    begin if rising_edge(clk) then
        if mr='0' and mw='0' then ack<='0';ticks:=0;
        elsif ack='0' then
            if ticks=ACK_DELAY then
                ack<='1';
                if mw='1' then last_word<=wd;writes<=writes+1;end if;
            else ticks:=ticks+1;end if;
        end if;
    end if;end process;
    process
        variable ref:bytes_t:=(others=>0);
        variable value,idx,checks:natural:=0;
        constant partition_pattern:bytes_t:=(0,0,0,25,0,0,0,25,0,0,16,0,0,0,16,0);
        procedure send(command:boolean;v:natural) is begin
            wait until falling_edge(clk);cs<='1';wr<='1';din<=std_logic_vector(to_unsigned(v,8));
            if command then addr<="01";else addr<="00";end if;
            wait until falling_edge(clk);wait until falling_edge(clk);wr<='0';
            for delay in 1 to BUS_GAP loop wait until falling_edge(clk);end loop;
            cs<='0';
        end;
        procedure check_display is begin
            assert to_integer(unsigned(b0))=ref(0)+256*ref(1)+65536*(ref(2) mod 4)
                report "PRAM upper half corrupted display base0" severity failure;
            assert to_integer(unsigned(b1))=ref(4)+256*ref(5)+65536*(ref(6) mod 4)
                report "PRAM upper half corrupted display base1" severity failure;
            assert to_integer(unsigned(l0))=ref(2)/16+16*(ref(3) mod 64)
                report "PRAM upper half corrupted partition0" severity failure;
            assert to_integer(unsigned(l1))=ref(6)/16+16*(ref(7) mod 64)
                report "PRAM upper half corrupted partition1" severity failure;
            -- Areas 3 and 4 share bytes 8-15 with the drawing pattern.
            assert to_integer(unsigned(b2))=ref(8)+256*(ref(9) mod 64)
                report "area 3 SAD mismatch" severity failure;
            assert to_integer(unsigned(b3))=ref(12)+256*(ref(13) mod 64)
                report "area 4 SAD mismatch" severity failure;
            assert to_integer(unsigned(l2))=ref(10)/16+16*(ref(11) mod 64)
                report "area 3 LEN mismatch" severity failure;
            assert to_integer(unsigned(l3))=ref(14)/16+16*(ref(15) mod 64)
                report "area 4 LEN mismatch" severity failure;
        end;
        procedure check_pattern is
            variable before,bit_value,physical_bit:natural;
            variable expected:std_logic_vector(15 downto 0);
        begin
            -- Exercise the actual line drawing datapath, one pixel at each
            -- bit position. This observes PRAM8/9 through the VRAM bus.
            for dot in 0 to 15 loop
                send(true,16#49#);send(false,0);send(false,0);send(false,dot*16);
                send(true,16#4c#);send(false,16#0a#);send(false,1);send(false,0);
                before:=writes;send(true,16#6c#);
                for t in 1 to 1000 loop
                    exit when writes>before and mr='0' and mw='0' and ack='0';
                    wait until falling_edge(clk);
                end loop;
                assert writes=before+1 report "pattern draw failed to complete once" severity failure;
                bit_value:=(ref(8+dot/8)/(2**(dot mod 8))) mod 2;
                physical_bit:=(dot/8)*8+7-(dot mod 8);
                expected:=(others=>'0');
                if bit_value=1 then expected(physical_bit):='1';end if;
                assert last_word=expected report "PRAM drawing pattern mismatch" severity failure;
            end loop;
        end;
    begin
        wait for 101 ns;rstn<='1';wait for 100 ns;
        -- BIOS-style continuous PRAM load: last eight bytes are pattern data.
        send(true,16#70#);
        for i in 0 to 15 loop
            value:=(i*17+3) mod 256;ref(i):=value;send(false,value);check_display;
        end loop;
        check_pattern;
        -- All 16 start offsets. Writes beyond PRAM15 are ignored, not wrapped
        -- into display registers (MAME/NP2 command-length references).
        for start in 0 to 15 loop
            send(true,16#70#+start);
            for n in 0 to 31 loop
                idx:=start+n;value:=(start*31+n*13+7) mod 256;
                if idx<16 then ref(idx):=value;end if;
                send(false,value);check_display;checks:=checks+1;
            end loop;
            check_pattern;
        end loop;
        -- PITCH is separate and ignores extra parameters.
        send(true,16#47#);send(false,40);send(false,99);
        assert unsigned(pitch)=40 report "extra PITCH parameter changed pitch" severity failure;
        -- A sixteen-byte load whose upper half would produce two one-row
        -- partitions at address0 under the old alias: exactly a repeated row.
        send(true,16#70#);
        for i in 0 to 15 loop send(false,partition_pattern(i));end loop;
        -- BIOS 200-line legacy mode leaves CSRFORM=1 before PEGC is enabled.
        -- Its actual decoder output must not double the packed 400-line frame.
        send(true,16#4b#);send(false,1);send(false,0);send(false,0);
        assert unsigned(legacy_rows)=1 report "CSRFORM control not decoded" severity failure;
        for y in 0 to 399 loop
            scan_h<=0;scan_row<=work.VIDEO_TIMING_pkg.VIV+y;wait for 1 ns;
            assert unsigned(scan_address)=y*80 report "PRAM stream repeated packed row" severity failure;
            wait until falling_edge(clk);scan_h<=1;wait until falling_edge(clk);
        end loop;
        -- Guest/core reset after the FIFO pointer has moved. No FPGA-power-up
        -- defaults are modelled for this production test.
        wait until falling_edge(clk);rstn<='0';wait for 31 ns;rstn<='1';wait for 100 ns;
        ref:=(others=>0);check_display;
        send(true,16#70#);ref(0):=37;send(false,37);check_display;
        report "PASS production GRAGDC PRAM addressing/bounds, drawing and reset, " & integer'image(checks) & " writes";
        done<=true;wait;
    end process;
end;
