library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity grcg_compare_tb is end;
architecture test of grcg_compare_tb is
    signal clk : std_logic := '0';
    signal rstn, iocs, iowr, ioaddr, cs, rd, wr : std_logic := '0';
    signal data : std_logic_vector(7 downto 0) := (others=>'0');
    signal addressed_plane : std_logic_vector(1 downto 0) := "00";
    type words_t is array(natural range <>) of std_logic_vector(15 downto 0);
    type planes_t is array(natural range <>) of std_logic_vector(3 downto 0);
    signal memory_data : words_t(0 to 3) := (others=>x"0000");
    signal result, w0, w1, w2, w3 : words_t(0 to 1);
    signal enables : planes_t(0 to 1);
    signal rd1, rd4, wr1, wr4, rmw1, rmw4, oe : std_logic_vector(0 to 1);
    constant tiles : words_t(0 to 3) := (x"5a5a",x"c3c3",x"9696",x"0f0f");
begin
    clk <= not clk after 5 ns;
    modes : for n in 0 to 1 generate
        dut : entity work.grcg generic map(SPLIT_RMW=>n=1)
            port map(iocs=>iocs,ioaddr=>ioaddr,iowr=>iowr,iowdat=>data,
                pmemcs=>cs,ppsel=>addressed_plane,prd=>rd,pwr=>wr,
                prddat=>result(n),pwrdat=>x"a53c",poe=>oe(n),
                memrd1=>rd1(n),memrd4=>rd4(n),memwr1=>wr1(n),memwr4=>wr4(n),
                memrmw1=>rmw1(n),memrmw4=>rmw4(n),
                memrdat0=>memory_data(0),memrdat1=>memory_data(1),
                memrdat2=>memory_data(2),memrdat3=>memory_data(3),
                memwdat0=>w0(n),memwdat1=>w1(n),memwdat2=>w2(n),memwdat3=>w3(n),
                memwmask=>open,memwrpsel=>enables(n),clk=>clk,rstn=>rstn);
    end generate;
    process
        variable random : unsigned(31 downto 0) := x"92a176cb";
        variable mask : unsigned(3 downto 0);
        variable pattern : words_t(0 to 3);
        variable expected : std_logic_vector(15 downto 0);
        variable checks : natural := 0;
        procedure out_port(tile : boolean; value : std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(clk);
            iocs<='1'; iowr<='1'; data<=value;
            if tile then ioaddr<='1'; else ioaddr<='0'; end if;
            -- Held I/O strobes must still load precisely one tile slot.
            for hold in 1 to 3 loop wait until falling_edge(clk); end loop;
            iowr<='0';
            wait until falling_edge(clk);
        end;
        procedure load_tiles is
        begin
            for p in 0 to 3 loop out_port(true,tiles(p)(7 downto 0)); end loop;
        end;
        procedure compare is
        begin
            memory_data<=pattern;
            wait for 1 ns;
            -- Pixel-wise reference, independent of the RTL XOR/AND tree.
            expected:=(others=>'1');
            for bit_no in 0 to 15 loop
                for p in 0 to 3 loop
                    if mask(p)='1' and pattern(p)(bit_no)/=tiles(p)(bit_no) then
                        expected(bit_no):='0';
                    end if;
                end loop;
            end loop;
            for n in 0 to 1 loop
                assert result(n)=expected report "GRCG compare mismatch" severity failure;
                assert rd4(n)='1' and rd1(n)='0' and oe(n)='1'
                    report "GRCG compare did not request all four planes" severity failure;
                assert enables(n)=std_logic_vector(mask)
                    report "GRCG enabled-plane polarity changed" severity failure;
            end loop;
            checks:=checks+1;
        end;
    begin
        wait until falling_edge(clk); rstn<='1'; cs<='1'; rd<='1';
        -- Also test tile-pointer restart after every possible partial load.
        for partial in 1 to 3 loop
            out_port(false,x"80");
            for p in 1 to partial loop out_port(true,x"ff"); end loop;
            out_port(false,x"80"); load_tiles;
            mask:="1111"; pattern:=tiles; compare;
        end loop;
        for subset in 0 to 15 loop
            mask:=to_unsigned(subset,4);
            out_port(false,x"8" & std_logic_vector(not mask)); load_tiles;
            for alias_plane in 0 to 3 loop
                addressed_plane<=std_logic_vector(to_unsigned(alias_plane,2));
                pattern:=tiles; compare;
                for p in 0 to 3 loop
                    for bit_no in 0 to 15 loop
                        pattern:=tiles;
                        pattern(p)(bit_no):=not pattern(p)(bit_no);
                        compare;
                    end loop;
                end loop;
                for trial in 1 to 128 loop
                    for p in 0 to 3 loop
                        random:=random(30 downto 0) &
                            (random(31) xor random(21) xor random(1) xor random(0));
                        pattern(p):=std_logic_vector(random(15 downto 0));
                    end loop;
                    compare;
                end loop;
            end loop;
        end loop;
        cs<='0'; wait for 1 ns;
        assert rd1="00" and rd4="00" and oe="00"
            report "GRCG read escaped chip select" severity failure;
        cs<='1'; rd<='0'; wait for 1 ns;
        assert rd1="00" and rd4="00" and oe="00"
            report "GRCG read escaped read strobe" severity failure;
        rd<='1';
        -- Normal and RMW reads must keep the one-plane path and raw data.
        for rmw in 0 to 1 loop
            if rmw=0 then out_port(false,x"00"); else out_port(false,x"c0"); end if;
            for trial in 1 to 128 loop
                memory_data(0)<=std_logic_vector(to_unsigned(trial*503,16));
                wait for 1 ns;
                for n in 0 to 1 loop
                    assert result(n)=memory_data(0) and rd1(n)='1' and rd4(n)='0'
                        report "GRCG normal/RMW read changed" severity failure;
                end loop;
            end loop;
        end loop;
        report "PASS GRCG: " & natural'image(checks) &
            " four-plane comparisons in both merge modes, partial tile restart, raw reads and select gating" severity note;
        finish;
    end process;
end;
