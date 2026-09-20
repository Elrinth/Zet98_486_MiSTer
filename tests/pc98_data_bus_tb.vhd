-- Tests the actual top-level bus expressions, inserted by run-data-bus.sh.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity pc98_data_bus_tb is end entity;
architecture test of pc98_data_bus_tb is
    signal legacy_bus : std_logic_vector(15 downto 0);
    signal enables : std_logic_vector(33 downto 0) := (others => '0');
    alias BNK89_DOE : std_logic is enables(0);
    signal BNK89_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias BNKAB_DOE : std_logic is enables(1);
    signal BNKAB_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias CB_RD1 : std_logic is enables(2);
    signal CB_RDAT0 : std_logic_vector(15 downto 0) := (others => '0');
    alias COM_DOE : std_logic is enables(3);
    signal COM_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias DBIO_DOE : std_logic is enables(4);
    signal DBIO_ODAT : std_logic_vector(15 downto 0) := (others => '0');
    alias DMA_DOE : std_logic is enables(5);
    signal DMA_H2L : std_logic := '0';
    signal DMA_L2H : std_logic := '0';
    signal DMA_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    signal DMAen : std_logic := '0';
    alias FDCIFS_DOE : std_logic is enables(6);
    signal FDCIFS_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias FDCNT_DOE : std_logic is enables(7);
    signal FDCNT_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias FDC_DOE : std_logic is enables(8);
    signal FDC_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias FDIBM_DOE : std_logic is enables(9);
    signal FDIBM_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias GCG_DOE : std_logic is enables(10);
    signal GCG_ODAT : std_logic_vector(15 downto 0) := (others => '0');
    alias GPAL_DOE : std_logic is enables(11);
    signal GPAL_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias IDE_DOE : std_logic is enables(12);
    signal IDE_ODAT : std_logic_vector(15 downto 0) := (others => '0');
    alias IN00f0_DOE : std_logic is enables(13);
    signal IN00f0_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    signal INTM_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias INTM_OE : std_logic is enables(14);
    signal INTS_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias INTS_OE : std_logic is enables(15);
    alias IO439_DOE : std_logic is enables(16);
    signal IO439_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    signal KBod : std_logic_vector(7 downto 0) := (others => '0');
    alias KBoe : std_logic is enables(17);
    alias KNJ0_DOE : std_logic is enables(18);
    signal KNJ0_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias KNJ1_DOE : std_logic is enables(19);
    signal KNJ1_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias KNJ2_DOE : std_logic is enables(20);
    signal KNJ2_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias LDR_OE : std_logic is enables(21);
    signal LDR_WDAT : std_logic_vector(7 downto 0) := (others => '0');
    alias MOUS_DOE : std_logic is enables(22);
    signal MOUS_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias NVR_DOE : std_logic is enables(23);
    signal NVR_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias OPN_DOE : std_logic is enables(24);
    signal OPN_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias PTC_DOE : std_logic is enables(25);
    signal PTC_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    signal SNDID_ODAT : std_logic_vector(7 downto 0) := (others => '0');
    alias SNDID_OE : std_logic is enables(26);
    alias SYSP_DOE : std_logic is enables(27);
    signal SYSP_RDAT : std_logic_vector(7 downto 0) := (others => '0');
    alias TSTMP_DOE : std_logic is enables(28);
    signal TSTMP_ODAT : std_logic_vector(15 downto 0) := (others => '0');
    signal aramdo : std_logic_vector(15 downto 0) := (others => '0');
    signal aramdoe : std_logic_vector(1 downto 0) := (others => '0');
    signal bussel : std_logic_vector(1 downto 0) := (others => '0');
    signal cpuod : std_logic_vector(15 downto 0) := (others => '0');
    alias cpuoe : std_logic is enables(29);
    signal cpusel : std_logic_Vector(1 downto 0) := (others => '0');
    signal dbus : std_logic_vector(15 downto 0) := (others => '0');
    signal dbus_high : std_logic_vector(8 downto 0) := (others => '0');
    signal dbus_low : std_logic_vector(8 downto 0) := (others => '0');
    signal gGDCod : std_logic_vector(7 downto 0) := (others => '0');
    alias gGDCoe : std_logic is enables(30);
    signal ioaddr_odd : std_logic_vector(15 downto 0) := (others => '0');
    alias iord : std_logic is enables(31);
    signal prnod : std_logic_vector(7 downto 0) := (others => '0');
    alias prnoe : std_logic is enables(32);
    signal tGDCod : std_logic_vector(7 downto 0) := (others => '0');
    alias tGDCoe : std_logic is enables(33);
    signal tgca : std_logic := '0';
    signal tramdo : std_logic_vector(15 downto 0) := (others => '0');
    signal tramdoe : std_logic_vector(1 downto 0) := (others => '0');
begin
    process
        variable random : unsigned(31 downto 0) := x"98c0ffee";
        variable cases : natural := 0;
        procedure advance is
        begin
            random := random xor shift_left(random, 13);
            random := random xor shift_right(random, 17);
            random := random xor shift_left(random, 5);
        end procedure;
        procedure data_pattern is
        begin
            advance;
            BNK89_ODAT <= std_logic_vector(resize(random, BNK89_ODAT'length));
            advance;
            BNKAB_ODAT <= std_logic_vector(resize(random, BNKAB_ODAT'length));
            advance;
            CB_RDAT0 <= std_logic_vector(resize(random, CB_RDAT0'length));
            advance;
            COM_ODAT <= std_logic_vector(resize(random, COM_ODAT'length));
            advance;
            DBIO_ODAT <= std_logic_vector(resize(random, DBIO_ODAT'length));
            advance;
            DMA_ODAT <= std_logic_vector(resize(random, DMA_ODAT'length));
            advance;
            FDCIFS_ODAT <= std_logic_vector(resize(random, FDCIFS_ODAT'length));
            advance;
            FDCNT_ODAT <= std_logic_vector(resize(random, FDCNT_ODAT'length));
            advance;
            FDC_ODAT <= std_logic_vector(resize(random, FDC_ODAT'length));
            advance;
            FDIBM_ODAT <= std_logic_vector(resize(random, FDIBM_ODAT'length));
            advance;
            GCG_ODAT <= std_logic_vector(resize(random, GCG_ODAT'length));
            advance;
            GPAL_ODAT <= std_logic_vector(resize(random, GPAL_ODAT'length));
            advance;
            IDE_ODAT <= std_logic_vector(resize(random, IDE_ODAT'length));
            advance;
            IN00f0_ODAT <= std_logic_vector(resize(random, IN00f0_ODAT'length));
            advance;
            INTM_ODAT <= std_logic_vector(resize(random, INTM_ODAT'length));
            advance;
            INTS_ODAT <= std_logic_vector(resize(random, INTS_ODAT'length));
            advance;
            IO439_ODAT <= std_logic_vector(resize(random, IO439_ODAT'length));
            advance;
            KBod <= std_logic_vector(resize(random, KBod'length));
            advance;
            KNJ0_ODAT <= std_logic_vector(resize(random, KNJ0_ODAT'length));
            advance;
            KNJ1_ODAT <= std_logic_vector(resize(random, KNJ1_ODAT'length));
            advance;
            KNJ2_ODAT <= std_logic_vector(resize(random, KNJ2_ODAT'length));
            advance;
            LDR_WDAT <= std_logic_vector(resize(random, LDR_WDAT'length));
            advance;
            MOUS_ODAT <= std_logic_vector(resize(random, MOUS_ODAT'length));
            advance;
            NVR_ODAT <= std_logic_vector(resize(random, NVR_ODAT'length));
            advance;
            OPN_ODAT <= std_logic_vector(resize(random, OPN_ODAT'length));
            advance;
            PTC_ODAT <= std_logic_vector(resize(random, PTC_ODAT'length));
            advance;
            SNDID_ODAT <= std_logic_vector(resize(random, SNDID_ODAT'length));
            advance;
            SYSP_RDAT <= std_logic_vector(resize(random, SYSP_RDAT'length));
            advance;
            TSTMP_ODAT <= std_logic_vector(resize(random, TSTMP_ODAT'length));
            advance;
            aramdo <= std_logic_vector(resize(random, aramdo'length));
            advance;
            aramdoe <= std_logic_vector(resize(random, aramdoe'length));
            advance;
            bussel <= std_logic_vector(resize(random, bussel'length));
            advance;
            cpuod <= std_logic_vector(resize(random, cpuod'length));
            advance;
            cpusel <= std_logic_vector(resize(random, cpusel'length));
            advance;
            gGDCod <= std_logic_vector(resize(random, gGDCod'length));
            advance;
            ioaddr_odd <= std_logic_vector(resize(random, ioaddr_odd'length));
            advance;
            prnod <= std_logic_vector(resize(random, prnod'length));
            advance;
            tGDCod <= std_logic_vector(resize(random, tGDCod'length));
            advance;
            tramdo <= std_logic_vector(resize(random, tramdo'length));
            advance;
            tramdoe <= std_logic_vector(resize(random, tramdoe'length));
        end procedure;
        procedure check is
        begin
            wait for 1 ns;
            assert dbus = legacy_bus report "Data bus differs from legacy priority/routing" severity failure;
            cases := cases + 1;
        end procedure;
        procedure routes is
        begin
            DMA_H2L <= '0'; DMA_L2H <= '0'; check;
            DMA_H2L <= '1'; DMA_L2H <= '0'; check;
            DMA_H2L <= '0'; DMA_L2H <= '1'; check;
        end procedure;
    begin
        -- Every pair of device enables, including a single enabled device.
        -- Preserve native lane masks and exercise CPU takeover suppression.
        for mask in 0 to 3 loop
            for a in enables'range loop
                for b in enables'range loop
                    data_pattern;
                    enables <= (others => '0'); enables(a) <= '1'; enables(b) <= '1';
                    cpusel <= std_logic_vector(to_unsigned(mask, 2));
                    bussel <= std_logic_vector(to_unsigned(mask, 2));
                    tramdoe <= std_logic_vector(to_unsigned(mask, 2));
                    aramdoe <= std_logic_vector(to_unsigned(mask, 2));
                    ioaddr_odd <= x"043b";
                    DMAen <= '0'; tgca <= '0'; routes;
                    DMAen <= '1'; tgca <= '1'; routes;
                end loop;
            end loop;
        end loop;
        -- Sparse random selections reach lower-priority devices as well.
        for trial in 1 to 10000 loop
            data_pattern;
            for e in enables'range loop
                advance;
                if random(3 downto 0) = 0 then enables(e) <= '1'; else enables(e) <= '0'; end if;
            end loop;
            DMAen <= random(8); tgca <= random(9);
            routes;
        end loop;
        -- FDC byte 5A must reach either memory lane; memory B6/C3 must
        -- reach the FDC low lane for even/odd DMA memory addresses.
        enables <= (others => '0'); tramdoe <= "00"; aramdoe <= "00";
        DMAen <= '1'; DMA_H2L <= '0'; DMA_L2H <= '0';
        FDC_DOE <= '1'; FDC_ODAT <= x"5a"; check;
        assert dbus = x"ff5a" severity failure;
        DMA_L2H <= '1'; check;
        assert dbus = x"5a5a" severity failure;
        FDC_DOE <= '0'; CB_RD1 <= '1'; CB_RDAT0 <= x"b6c3"; bussel <= "01";
        check;
        assert dbus = x"c3c3" severity failure;
        bussel <= "10"; DMA_L2H <= '0'; DMA_H2L <= '1'; check;
        assert dbus = x"b6b6" severity failure;
        report "PASS: actual PC-98 bus versus legacy: " & natural'image(cases) & " cases, device priority and DMA byte routing" severity note;
        finish;
    end process;
    -- The runner appends the production mux and historical reference here.
end architecture;
