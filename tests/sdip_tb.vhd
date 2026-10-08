-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity sdip_tb is end;
architecture test of sdip_tb is
    signal clk : std_logic := '0';
    signal rstn, rd, wr, oe : std_logic := '0';
    signal ea, oa : std_logic_vector(15 downto 0) := x"FFFF";
    signal wd : std_logic_vector(15 downto 0) := x"0000";
    signal legacy : std_logic_vector(7 downto 0) := x"E3";
    signal data, dips : std_logic_vector(7 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.pc98_sdip port map(clk,rstn,ea,oa,rd,wr,wd,legacy,data,dips,oe);
    process
        procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure write_port(a, value : natural) is
        begin
            ea<=x"FFFF"; oa<=x"FFFF";
            if a mod 2=0 then ea<=std_logic_vector(to_unsigned(a,16));
                wd<=std_logic_vector(to_unsigned(value,16));
            else oa<=std_logic_vector(to_unsigned(a,16));
                wd<=std_logic_vector(to_unsigned(value*256,16)); end if;
            wr<='1'; tick; tick; tick; wr<='0'; tick;
        end;
        procedure read_port(a, value : natural) is
        begin
            oa<=x"FFFF"; ea<=std_logic_vector(to_unsigned(a,16)); rd<='1';
            tick; tick;
            assert oe='1' and data=std_logic_vector(to_unsigned(value,8))
                report "SDIP read mismatch at " & integer'image(a) severity failure;
            rd<='0'; tick; assert oe='0' severity failure;
        end;
    begin
        tick; rstn<='1'; tick;
        assert dips=x"E3" report "Legacy DIP changed before use" severity failure;
        for b in 0 to 1 loop
            write_port(16#8F1F#,16#80#+b*64);
            for n in 0 to 11 loop
                read_port(16#841E#+n*256,255);
                write_port(16#841E#+n*256,b*64+n);
            end loop;
        end loop;
        for b in 0 to 1 loop
            write_port(16#8F1F#,16#80#+b*64);
            for n in 0 to 11 loop
                if b=0 and n=1 then read_port(16#851E#,16#91#);
                else read_port(16#841E#+n*256,b*64+n); end if;
            end loop;
        end loop;
        write_port(16#8F1F#,16#81#); read_port(16#841E#,64);
        -- Odd-only word partner must not write the even register.
        write_port(16#851F#,16#AA#); read_port(16#851E#,65);
        rstn<='0'; tick; rstn<='1'; tick;
        read_port(16#841E#,0); -- reset bank, retain storage
        write_port(16#851E#,16#F3#); write_port(16#871E#,0);
        assert dips=x"E3" report "Parity bit leaked into PPI" severity failure;
        write_port(16#871E#,16#20#);
        assert dips=x"F3" report "MEMSW init translation failed" severity failure;
        write_port(16#8F1F#,16#C0#); write_port(16#851E#,0);
        assert dips=x"F3" report "Bank 1 changed legacy DIP" severity failure;
        -- Simultaneous low-byte register + high-byte bank command: one write
        -- to the old bank, even when the bus strobe remains asserted.
        ea<=x"8F1E"; oa<=x"8F1F"; wd<=x"80A5"; wr<='1';
        tick; tick; tick; wr<='0'; tick;
        read_port(16#8F1E#,11);
        write_port(16#8F1F#,16#C0#); read_port(16#8F1E#,16#A5#);
        read_port(16#0534#,0); write_port(16#0534#,255); read_port(16#0534#,0);
        ea<=x"831E"; rd<='1'; tick; assert oe='0' severity failure;
        ea<=x"901E"; tick; assert oe='0' severity failure;
        ea<=x"841C"; tick; assert oe='0' severity failure;
        -- Native factory value: parity remains odd; MEMSW is separate.
        write_port(16#8F1F#,16#80#);
        write_port(16#851E#,16#73#);
        read_port(16#851E#,16#E3#);
        assert dips=x"F3" report "OSD GDC lost to native factory default" severity failure;
        legacy<=x"63"; tick; tick;
        read_port(16#851E#,16#E3#);
        assert dips(7)='1' report "Clock changed without reset" severity failure;
        rstn<='0'; tick; rstn<='1'; tick;
        read_port(16#851E#,16#73#);
        assert dips=x"73" report "Reset did not apply 5 MHz" severity failure;
        -- Exhaust every stored byte, including bad parity and erased FFh.
        -- Only GDC and its parity bit may change. Bank 1 must stay verbatim.
        for speed in 0 to 1 loop
            if speed=0 then legacy<=x"63"; else legacy<=x"E3"; end if;
            rstn<='0'; tick; rstn<='1'; tick;
            for raw in 0 to 255 loop
                write_port(16#851E#,raw);
                if (raw / 128)=speed then read_port(16#851E#,raw);
                else read_port(16#851E#,to_integer(to_unsigned(raw,8) xor x"90")); end if;
                assert dips(7)=legacy(7) report "PPI GDC disagrees with reset setting" severity failure;
                assert to_integer(unsigned(dips(6 downto 5)))=(raw/32) mod 4
                    and to_integer(unsigned(dips(3 downto 0)))=raw mod 16
                    report "Unrelated software switches altered" severity failure;
            end loop;
            write_port(16#8F1F#,16#C0#);
            for raw in 0 to 255 loop
                write_port(16#851E#,raw); read_port(16#851E#,raw);
            end loop;
            write_port(16#8F1F#,16#80#);
        end loop;
        report "PASS: SDIP banks, retention, byte lanes, PPI translation and CPU mode";
        stop;
    end process;
end architecture;
