library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Model only the existing 2048x8 synchronous dual-port primitive. The bank
-- decoder, RAM instances, font mapper and loader below are production RTL.
entity DPSRAM11x8 is
    port(address_a,address_b : in std_logic_vector(10 downto 0);
         clock_a,clock_b : in std_logic;
         data_a,data_b : in std_logic_vector(7 downto 0);
         wren_a,wren_b : in std_logic;
         q_a,q_b : out std_logic_vector(7 downto 0));
end;
architecture model of DPSRAM11x8 is
begin
    process(clock_a,clock_b)
        type ram_t is array(0 to 2047) of std_logic_vector(7 downto 0);
        variable ram : ram_t := (others=>(others=>'0'));
        variable a,b : natural;
    begin
        if rising_edge(clock_a) then
            a:=to_integer(unsigned(address_a));
            if wren_a='1' then ram(a):=data_a; end if;
            q_a<=ram(a);
        end if;
        if rising_edge(clock_b) then
            b:=to_integer(unsigned(address_b));
            if wren_b='1' then ram(b):=data_b; end if;
            q_b<=ram(b);
        end if;
    end process;
end;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity font_tail_ram_tb is end;
architecture test of font_tail_ram_tb is
    signal cpu_clk,pixel_clk : std_logic := '0';
    signal rstn,load_enable,load_write,io_write : std_logic := '0';
    signal load_address : std_logic_vector(19 downto 0) := x"80000";
    signal load_data,io_data,font_data,q_cpu,q_pixel : std_logic_vector(7 downto 0) := (others=>'0');
    signal io_address : std_logic_vector(15 downto 0) := (others=>'0');
    signal font_address,pixel_address : std_logic_vector(16 downto 0) := (others=>'0');
    signal bank : std_logic_vector(1 downto 0);
    signal font_write,tail_write,pixel_write : std_logic := '0';
    function pattern(offset : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned((offset*73+offset/2048*19+41) mod 256,8));
    end;
begin
    cpu_clk<=not cpu_clk after 5 ns;
    pixel_clk<=not pixel_clk after 7 ns;
    controller : entity work.KNJRAMCONT generic map(LDR_AWIDTH=>20) port map(
        LDR_ADDR=>load_address,LDR_EN=>load_enable,LDR_WR=>load_write,LDR_WDAT=>load_data,
        ioaddr=>io_address,iowr=>io_write,iord=>'1',wrdat=>io_data,
        KNJRAMSEL=>bank,KNJRAMADDR=>font_address,KNJRAMWDAT=>font_data,
        KNJRAMWR=>font_write,KNJRAMOE=>open,clk=>cpu_clk,rstn=>rstn);
    tail_write<=font_write when bank="10" else '0';
    tail : entity work.GAIJIRAMDP port map(
        address_a=>pixel_address,address_b=>font_address,
        clock_a=>pixel_clk,clock_b=>cpu_clk,data_a=>x"ff",data_b=>font_data,
        wren_a=>pixel_write,wren_b=>tail_write,q_a=>q_pixel,q_b=>q_cpu);
    process
        procedure output(port_number,value : natural) is
        begin
            wait until falling_edge(cpu_clk);
            io_address<=std_logic_vector(to_unsigned(port_number,16));
            io_data<=std_logic_vector(to_unsigned(value,8)); io_write<='1';
            wait until falling_edge(cpu_clk); io_write<='0';
            wait until falling_edge(cpu_clk);
        end;
        procedure pixel_read(offset : natural; expected : std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(pixel_clk);
            pixel_address<=std_logic_vector(to_unsigned(offset,17));
            wait until rising_edge(pixel_clk); wait for 1 ns;
            assert q_pixel=expected report "Font tail pixel data mismatch at " & integer'image(offset) severity failure;
        end;
        variable offset,cpu_samples : natural := 0;
    begin
        wait for 27 ns; rstn<='1'; load_enable<='1';
        for i in 0 to 16#67ff# loop
            wait until falling_edge(cpu_clk);
            load_address<=std_logic_vector(to_unsigned(16#80000#+i,20));
            load_data<=pattern(i); load_write<='1';
        end loop;
        wait until falling_edge(cpu_clk); load_write<='0'; load_enable<='0';
        for i in 0 to 16#67ff# loop pixel_read(i,pattern(i)); end loop;
        -- Addresses outside the actual tail must neither read nor alias RAM.
        for i in 16#6800# to 16#1ffff# loop
            wait until falling_edge(pixel_clk);
            pixel_address<=std_logic_vector(to_unsigned(i,17)); pixel_write<='1';
            wait until rising_edge(pixel_clk); wait for 1 ns;
            assert q_pixel=x"00" report "Font tail out-of-range read aliased RAM" severity failure;
        end loop;
        wait until falling_edge(pixel_clk); pixel_write<='0';
        for i in 0 to 16#67ff# loop pixel_read(i,pattern(i)); end loop;
        -- Read every stored tail byte through the actual CPU font-port mapper.
        for jis_row in 84 to 92 loop
            output(16#a3#,jis_row);
            for code in 32 to 127 loop
                output(16#a1#,code);
                for half in 0 to 1 loop
                    for row in 0 to 15 loop
                        offset:=16#1800#+(jis_row-1)*3072+(code-32)*32+half*16+row;
                        if offset>=16#40000# then
                            output(16#a5#,(1-half)*32+row);
                            assert bank="10" and q_cpu=pattern(offset-16#40000#)
                                report "Font tail CPU data mismatch at " & integer'image(offset) severity failure;
                            cpu_samples:=cpu_samples+1;
                        end if;
                    end loop;
                end loop;
            end loop;
        end loop;
        assert cpu_samples=16#6800# report "Tail CPU test coverage changed" severity failure;
        -- Both ends of the original custom-character window remain writable.
        output(16#a1#,16#20#); output(16#a3#,16#56#); output(16#a5#,32);
        output(16#a9#,16#5a#);
        assert q_cpu=x"5a" report "Custom-character first byte not writable" severity failure;
        pixel_read(16#1400#,x"5a");
        output(16#a1#,16#7f#); output(16#a3#,16#57#); output(16#a5#,15);
        output(16#a9#,16#a5#);
        assert q_cpu=x"a5" report "Custom-character last byte not writable" severity failure;
        pixel_read(16#2bff#,x"a5");
        report "PASS: 26624 tail bytes loaded/read on CPU and pixel ports; 104448 out-of-range addresses; custom writes preserved";
        finish;
    end process;
end;
