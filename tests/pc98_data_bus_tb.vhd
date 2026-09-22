-- Tests the actual top-level bus expressions, inserted by run-data-bus.sh.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity pc98_data_bus_tb is end entity;
architecture test of pc98_data_bus_tb is
    signal pMPUReadData : std_logic_vector(7 downto 0) := x"5a";
    signal pMPUOE : std_logic := '0';
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
    signal io_wdata : std_logic_vector(15 downto 0);
    signal mem_wdata : std_logic_vector(15 downto 0);
    signal fdc_wdata : std_logic_vector(7 downto 0);
    signal dma_mem_high, dma_mem_low : std_logic_vector(8 downto 0);
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
    signal clk : std_logic := '0';
    signal rstn, grcg_ioaddr, grcg_iowr, grcg_write : std_logic := '0';
    type planes_t is array(0 to 3) of std_logic_vector(15 downto 0);
    signal plane_read, plane_write : planes_t := (others => (others => '0'));
    constant tiles : planes_t := (x"5a5a", x"c3c3", x"9696", x"0f0f");
    signal rmw4, wr1, wr4 : std_logic;
    signal plane_select : std_logic_vector(3 downto 0);
    signal grcg_ppsel : std_logic_vector(1 downto 0) := "00";
    signal grcg_rdata : std_logic_vector(15 downto 0);
    signal split_write : planes_t;
    signal split_mask : std_logic_vector(15 downto 0);
begin
    clk <= not clk after 5 ns;
    graphics : entity work.grcg
        port map(iocs=>'1', ioaddr=>grcg_ioaddr, iowr=>grcg_iowr,
            iowdat=>io_wdata(7 downto 0), pmemcs=>'1', ppsel=>grcg_ppsel,
            prd=>'0', pwr=>grcg_write, prddat=>grcg_rdata, pwrdat=>mem_wdata, poe=>open,
            memrd1=>open, memrd4=>open, memwr1=>wr1, memwr4=>wr4,
            memrmw1=>open, memrmw4=>rmw4,
            memrdat0=>plane_read(0), memrdat1=>plane_read(1),
            memrdat2=>plane_read(2), memrdat3=>plane_read(3),
            memwdat0=>plane_write(0), memwdat1=>plane_write(1),
            memwdat2=>plane_write(2), memwdat3=>plane_write(3),
            memwmask=>open, memwrpsel=>plane_select, clk=>clk, rstn=>rstn);
    split_graphics : entity work.grcg generic map(SPLIT_RMW=>true)
        port map(iocs=>'1', ioaddr=>grcg_ioaddr, iowr=>grcg_iowr,
            iowdat=>io_wdata(7 downto 0), pmemcs=>'1', ppsel=>grcg_ppsel,
            prd=>'0', pwr=>grcg_write, prddat=>open, pwrdat=>mem_wdata, poe=>open,
            memrd1=>open, memrd4=>open, memwr1=>open, memwr4=>open,
            memrmw1=>open, memrmw4=>open,
            memrdat0=>plane_read(0), memrdat1=>plane_read(1),
            memrdat2=>plane_read(2), memrdat3=>plane_read(3),
            memwdat0=>split_write(0), memwdat1=>split_write(1),
            memwdat2=>split_write(2), memwdat3=>split_write(3),
            memwmask=>split_mask, memwrpsel=>open, clk=>clk, rstn=>rstn);
    process
        variable random : unsigned(31 downto 0) := x"98c0ffee";
        variable cases : natural := 0;
        variable write_lanes : natural := 0;
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
            -- Peripheral writes sample only their selected CPU lane. Check
            -- that bypassing all read devices preserves those sampled bytes,
            -- including simultaneous even/odd writes and loader precedence.
            if LDR_OE='1' then
                assert io_wdata = legacy_bus report "I/O loader override changed" severity failure;
                assert mem_wdata = legacy_bus and fdc_wdata = legacy_bus(7 downto 0)
                    report "Memory/FDC loader override changed" severity failure;
                write_lanes := write_lanes + 2;
            elsif cpuoe='1' and DMAen='0' then
                if cpusel(0)='1' then
                    assert io_wdata(7 downto 0) = legacy_bus(7 downto 0)
                        report "Even I/O write byte changed" severity failure;
                    assert mem_wdata(7 downto 0)=legacy_bus(7 downto 0) and fdc_wdata=legacy_bus(7 downto 0)
                        report "CPU low memory/FDC write byte changed" severity failure;
                    write_lanes := write_lanes + 1;
                end if;
                if cpusel(1)='1' then
                    assert io_wdata(15 downto 8) = legacy_bus(15 downto 8)
                        report "Odd I/O write byte changed" severity failure;
                    assert mem_wdata(15 downto 8)=legacy_bus(15 downto 8)
                        report "CPU high memory write byte changed" severity failure;
                    write_lanes := write_lanes + 1;
                end if;
            end if;
            cases := cases + 1;
        end procedure;
        procedure routes is
        begin
            DMA_H2L <= '0'; DMA_L2H <= '0'; check;
            DMA_H2L <= '1'; DMA_L2H <= '0'; check;
            DMA_H2L <= '0'; DMA_L2H <= '1'; check;
        end procedure;
    begin
        -- The newly added MPU occupies only the low byte. Exercise the actual
        -- production mux before the unchanged-device equivalence checks.
        pMPUOE<='1'; wait for 1 ns;
        assert dbus=x"ff5a" report "MPU did not drive just the low byte" severity failure;
        cpuoe<='1'; cpusel<="11"; cpuod<=x"c391"; wait for 1 ns;
        assert dbus=x"c391" report "MPU overrode CPU write lanes" severity failure;
        cpuoe<='0'; cpusel<="00"; pMPUOE<='0'; wait for 1 ns;
        report "PASS: MPU low-byte read and CPU write priority";
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
        -- Memory-to-FDC reads: preserve the old memory-device priorities with
        -- both DMA byte addresses. Unrelated I/O read enables are inactive.
        for trial in 1 to 5000 loop
            data_pattern;
            enables <= (others=>'0');
            GCG_DOE<=random(0); DBIO_DOE<=random(1); CB_RD1<=random(2);
            NVR_DOE<=random(3); LDR_OE<=random(4); cpuoe<=random(5);
            DMAen<='1';
            for odd in 0 to 1 loop
                if odd=0 then
                    bussel<="01"; DMA_H2L<='0'; DMA_L2H<='1';
                else
                    bussel<="10"; DMA_H2L<='1'; DMA_L2H<='0';
                end if;
                check;
                assert fdc_wdata=legacy_bus(7 downto 0)
                    report "DMA memory-to-FDC byte changed" severity failure;
            end loop;
            -- FDC-to-memory writes select just one memory byte lane.
            enables <= (others=>'0'); tramdoe<="00"; aramdoe<="00";
            FDC_DOE<=random(6); LDR_OE<=random(7);
            DMA_H2L<='1'; DMA_L2H<='0'; check;
            assert mem_wdata(7 downto 0)=legacy_bus(7 downto 0)
                report "DMA FDC-to-memory even byte changed" severity failure;
            DMA_H2L<='0'; DMA_L2H<='1'; check;
            assert mem_wdata(15 downto 8)=legacy_bus(15 downto 8)
                report "DMA FDC-to-memory odd byte changed" severity failure;
        end loop;
        report "PASS: 20000 DMA read/write byte-routing comparisons" severity note;

        -- Exercise the actual GRCG with the production write path. Its mask
        -- must remain live while a delayed SDRAM read supplies each plane.
        enables<=(others=>'0'); tramdoe<="00"; aramdoe<="00";
        DMAen<='0'; cpuoe<='1'; cpusel<="11";
        wait until falling_edge(clk); rstn<='1';
        grcg_ioaddr<='0'; cpuod<=x"00c0"; grcg_iowr<='1';
        wait until falling_edge(clk); grcg_iowr<='0';
        wait until falling_edge(clk);
        for p in 0 to 3 loop
            grcg_ioaddr<='1'; cpuod<=tiles(p); grcg_iowr<='1';
            wait until falling_edge(clk); grcg_iowr<='0';
            wait until falling_edge(clk);
        end loop;
        for trial in 1 to 256 loop
            advance; cpuod<=std_logic_vector(random(15 downto 0));
            FDC_ODAT<=std_logic_vector(random(23 downto 16));
            DMAen<=random(24); FDC_DOE<='1'; grcg_write<='1';
            for delay in 0 to 3 loop
                for p in 0 to 3 loop
                    advance; plane_read(p)<=std_logic_vector(random(15 downto 0));
                end loop;
                wait until falling_edge(clk);
                assert rmw4='1' and wr1='0' and wr4='0' and plane_select="1111"
                    report "GRCG RMW mode or plane enables changed" severity failure;
                for p in 0 to 3 loop
                    assert plane_write(p)=((tiles(p) and mem_wdata) or (plane_read(p) and not mem_wdata))
                        report "GRCG lost live write mask or delayed plane read" severity failure;
                    assert (split_write(p) or (plane_read(p) and split_mask))=plane_write(p)
                        report "Split GRCG set/preserve pair changed the RMW result" severity failure;
                end loop;
            end loop;
        end loop;
        report "PASS: actual GRCG live CPU/DMA masks and delayed SDRAM data, 4096 plane results" severity note;
        -- Comparison combines all enabled planes, independently of the
        -- addressed plane, while keeping high and low bytes distinct.
        DMAen<='0'; grcg_write<='0'; FDC_DOE<='0';
        grcg_ioaddr<='0'; cpuod<=x"0080"; grcg_iowr<='1';
        wait until falling_edge(clk); grcg_iowr<='0';
        wait until falling_edge(clk);
        for p in 0 to 3 loop
            grcg_ppsel<=std_logic_vector(to_unsigned(p, 2));
            plane_read<=tiles;
            plane_read(p)<=tiles(p)(15 downto 8) & not tiles(p)(7 downto 0);
            wait for 1 ns;
            assert grcg_rdata=x"ff00" report "GRCG compare lost high/low byte distinction" severity failure;
            plane_read(p)<=not tiles(p)(15 downto 8) & tiles(p)(7 downto 0);
            wait for 1 ns;
            assert grcg_rdata=x"00ff" report "GRCG compare lost low/high byte distinction" severity failure;
        end loop;
        report "PASS: graphics tile comparison reads both bytes on all four planes" severity note;
        report "PASS: actual PC-98 bus versus legacy: " & natural'image(cases) & " cases, device priority and DMA byte routing" severity note;
        assert write_lanes > 1000 report "Insufficient selected write-lane coverage" severity failure;
        report "PASS: direct CPU I/O write path: " & natural'image(write_lanes) & " selected bytes match historical shared bus" severity note;
        finish;
    end process;
    -- The runner appends the production mux and historical reference here.
end architecture;
