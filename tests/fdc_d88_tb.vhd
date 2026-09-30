-- D88 image -> diskemu_mister (MiSTer sd protocol, SDRAM track cache)
-- -> FDemu bit stream -> FDC, wired as in Zet98MiSTer.vhd. A BIOS-like
-- CPU/DMA model issues uPD765 commands and checks the transferred bytes
-- against the D88, the result bytes, and the command latency against the
-- NEC BIOS completion-interrupt timeout.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.FDC_timing.all;

package fdc_d88_pkg is
    type image_t is protected
        procedure load(name : string);
        impure function size return natural;
        impure function byte(a : natural) return natural;
        -- offset of the data of sector C/H/R/N on physical track t, or -1
        impure function find(t, c, h, r, n : natural) return integer;
        impure function nsec(t : natural) return natural;           -- 0: no track
        impure function id(t, i, k : natural) return natural;       -- header byte k: 0=C 1=H 2=R 3=N 6=density
    end protected;
    type memory_t is protected
        procedure write(a : natural; d : std_logic_vector(15 downto 0));
        impure function read(a : natural) return std_logic_vector;
    end protected;
end package;

package body fdc_d88_pkg is
    type image_t is protected body
        type bytes_t is array(natural range <>) of natural range 0 to 255;
        type bytes_ptr is access bytes_t;
        variable img : bytes_ptr := null;
        variable len : natural := 0;
        procedure load(name : string) is
            type char_file is file of character;
            file f : char_file;
            variable c : character;
            variable tmp : bytes_ptr;
        begin
            file_open(f, name, read_mode);
            img := new bytes_t(0 to 4*1024*1024-1);
            len := 0;
            while not endfile(f) loop
                read(f, c);
                img(len) := character'pos(c);
                len := len + 1;
            end loop;
            file_close(f);
        end procedure;
        impure function size return natural is begin return len; end function;
        impure function byte(a : natural) return natural is
        begin
            if a < len then return img(a); else return 0; end if;
        end function;
        impure function le16(a : natural) return natural is
        begin return byte(a) + 256*byte(a+1); end function;
        impure function le32(a : natural) return natural is
        begin return le16(a) + 65536*le16(a+2); end function;
        impure function find(t, c, h, r, n : natural) return integer is
            variable p, nsec : natural;
        begin
            p := le32(16#20# + 4*t);
            if p = 0 then return -1; end if;
            nsec := le16(p + 4);
            for i in 0 to nsec-1 loop
                if byte(p)=c and byte(p+1)=h and byte(p+2)=r and byte(p+3)=n then
                    return p + 16;
                end if;
                p := p + 16 + le16(p + 14);
            end loop;
            return -1;
        end function;
        impure function nsec(t : natural) return natural is
            variable p : natural;
        begin
            p := le32(16#20# + 4*t);
            if p = 0 then return 0; end if;
            return le16(p + 4);
        end function;
        impure function id(t, i, k : natural) return natural is
            variable p : natural;
        begin
            p := le32(16#20# + 4*t);
            for j in 1 to i loop p := p + 16 + le16(p + 14); end loop;
            return byte(p + k);
        end function;
    end protected body;

    type memory_t is protected body
        type words_t is array(natural range <>) of natural range 0 to 65535;
        type words_ptr is access words_t;
        variable m : words_ptr := null;
        procedure write(a : natural; d : std_logic_vector(15 downto 0)) is
        begin
            if m = null then m := new words_t(0 to 2**22-1); end if;
            m(a) := to_integer(unsigned(d));
        end procedure;
        impure function read(a : natural) return std_logic_vector is
        begin
            if m = null then m := new words_t(0 to 2**22-1); end if;
            return std_logic_vector(to_unsigned(m(a), 16));
        end function;
    end protected body;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.FDC_timing.all;
use work.fdc_d88_pkg.all;

entity fdc_d88_tb is
    generic(
        SYSFREQ : integer := 20000;          -- kHz, as Zet98MiSTer SYSFREQ
        IMAGE   : string  := "std.d88";
        TEST    : string  := "std";          -- std | fm | loh
        LAT     : positive := 12;            -- SDRAM completion latency (clocks)
        -- NEC BIOS FD80:2188 polls 28h*65536 times for the completion
        -- interrupt. On hardware (B228) a standard disk survives the boot's
        -- FM READ ID probe, which took 623 ms there, so the limit is above
        -- that; keep every command under it.
        LIMIT_MS : natural := 600;
        VERBOSE  : boolean := false;
        LOAD_MS  : positive := 400;          -- mount-to-ready budget (sim time)
        -- TEST=scan: read every present cylinder in [CYL_FIRST, CYL_LAST]
        -- (stepping CYL_STEP) with one MT READ DATA over both heads
        CYL_FIRST : natural := 0;
        CYL_LAST  : natural := 76;
        CYL_STEP  : positive := 1
    );
end entity;

architecture test of fdc_d88_tb is
    constant PERIOD : time := 1 ms / SYSFREQ;
    shared variable img : image_t;
    shared variable mem : memory_t;

    signal clk, rstn : std_logic := '0';

    -- MiSTer sd interface
    signal mist_mounted, mist_readonly, mist_rd, mist_wr : std_logic_vector(3 downto 0) := (others=>'0');
    signal mist_imgsize : std_logic_vector(63 downto 0) := (others=>'0');
    signal mist_lba : std_logic_vector(31 downto 0);
    signal mist_ack, mist_buffwr : std_logic := '0';
    signal mist_buffaddr : std_logic_vector(8 downto 0) := (others=>'0');
    signal mist_buffdout, mist_buffdin : std_logic_vector(7 downto 0) := (others=>'0');

    -- SDRAM ports
    signal FDE_RAMADDR : std_logic_vector(22 downto 0);
    signal FDE_RAMRDAT, FDE_RAMWDAT : std_logic_vector(15 downto 0) := (others=>'0');
    signal FDE_RAMWR, FDE_RAMWAIT : std_logic := '0';
    signal FEC_RAMADDRH : std_logic_vector(14 downto 0);
    signal FEC_RAMADDRL : std_logic_vector(7 downto 0);
    signal FEC_RAMWE, FEC_RAMRD, FEC_RAMWR, FEC_RAMBUSY : std_logic;
    signal FEC_RAMWDAT, FEC_RAMRDAT : std_logic_vector(15 downto 0);
    signal FEC_ADDR : std_logic_vector(22 downto 0);
    signal FEC_RD, FEC_WR, FEC_RAMWAIT : std_logic := '0';
    signal FEC_RDAT, FEC_WDAT : std_logic_vector(15 downto 0) := (others=>'0');

    -- FDC <-> drive
    signal FDE_READYn, FDE_WRENn, FDE_WRBITn, FDE_RDBITn, FDE_STEPn, FDE_SDIRn : std_logic;
    signal FDE_TRACK0n, FDE_INDEXn, FDE_SIDEn, FDE_WPROTn, FDE_MFM : std_logic;
    signal FDC_USEL : std_logic_vector(1 downto 0);
    signal FDC_USELbn : std_logic_vector(3 downto 0);
    signal FDC_int : integer range 0 to (BR_300_D*SYSFREQ/1000000);
    signal FDC_hmssft, FDC_BUSY, FDC_INTn, FDC_DRQ, FDC_DOE : std_logic;
    signal FDC_ODAT : std_logic_vector(7 downto 0);
    signal fdc_indisk : std_logic_vector(1 downto 0);
    -- port 94h bit 3 (the BIOS writes 08h/18h; Xanadu's own driver 10h/00h)
    signal FDC_MOTOR : std_logic := '1';
    constant FDC_FREADY : std_logic := '0';   -- drive READY counts (B228)
    constant FDC_H_Dn : std_logic := '1';     -- 1MB (2HD) interface

    -- CPU / DMA bus
    signal cpu_csn, cpu_rdn, cpu_wrn, dma_rdn, dma_dackn : std_logic := '1';
    signal dma_tc : std_logic := '0';
    signal fdc_rdn, fdc_tc, fdc_ready_in : std_logic;
    signal fdc_motorn : std_logic_vector(1 downto 0);
    signal cpu_a0 : std_logic := '0';
    signal cpu_wdat : std_logic_vector(7 downto 0) := (others=>'0');

    type buf_t is array(0 to 16383) of natural range 0 to 255;
    signal dmabuf : buf_t := (others=>0);
    signal dma_count : natural := 0;
    signal dma_len : natural := 0;
    signal dma_go : boolean := false;

    -- SDRAM behavioural model state (sdramc accept/busy protocol)
    signal fde_busy, fec_busy : std_logic := '0';
begin
    clk <= not clk after PERIOD/2;
    heartbeat : process
    begin
        wait for 10 ms;
        if VERBOSE then report "t=" & time'image(now) & " index=" & std_logic'image(FDE_INDEXn); end if;
    end process;

    -------------------------------------------------------------------------
    -- MiSTer hps_io sd model: mist_rd -> ack, 512 x buffwr, ack low.
    -------------------------------------------------------------------------
    host : process
        variable lba : natural;
    begin
        img.load(IMAGE);
        mist_imgsize <= std_logic_vector(to_unsigned(img.size, 64));
        wait until rstn='1';
        for i in 1 to 20 loop wait until rising_edge(clk); end loop;
        mist_mounted(0) <= '1';
        wait until rising_edge(clk);
        mist_mounted(0) <= '0';
        loop
            wait until rising_edge(clk);
            assert mist_wr="0000" report "unexpected image write-back" severity failure;
            if mist_rd(0)='1' then
                lba := to_integer(unsigned(mist_lba));
                if VERBOSE then report "mist read LBA " & integer'image(lba); end if;
                for i in 1 to 8 loop wait until rising_edge(clk); end loop;
                mist_ack <= '1';
                for i in 0 to 511 loop
                    wait until rising_edge(clk);
                    mist_buffaddr <= std_logic_vector(to_unsigned(i, 9));
                    mist_buffdout <= std_logic_vector(to_unsigned(img.byte(lba*512+i), 8));
                    mist_buffwr <= '1';
                    wait until rising_edge(clk);
                    mist_buffwr <= '0';
                end loop;
                wait until rising_edge(clk);
                mist_ack <= '0';
                wait until rising_edge(clk);
            end if;
        end loop;
    end process;

    -------------------------------------------------------------------------
    -- SDRAM ports: accept on new address/job while idle, WAIT(busy) for LAT
    -- clocks, read data registered on the completion edge (Zet98/sdramc.vhd).
    -------------------------------------------------------------------------
    sdram : process(clk)
        variable fde_cnt, fec_cnt : natural := 0;
        variable fde_ladr, fec_ladr : std_logic_vector(22 downto 0) := (others=>'0');
        variable fde_ljob, fec_ljob : std_logic := '0';   -- '1' write
        variable fde_lstb, fec_lstb : std_logic := '0';
        variable fde_wd, fec_wd : std_logic_vector(15 downto 0);
        variable acc : boolean;
        constant FDERD : std_logic := '1';
        variable FDEWR : std_logic;
    begin
        if rising_edge(clk) then
            if rstn='0' then
                fde_busy <= '0'; fec_busy <= '0'; fde_lstb := '0'; fec_lstb := '0';
            else
                -- FDE (FDERD = not FDE_RAMWR in Zet98MiSTer)
                FDEWR := FDE_RAMWR;
                acc := fde_busy='0' and (fde_lstb='0' or fde_ladr/=FDE_RAMADDR or fde_ljob/=FDEWR);
                fde_lstb := '1';
                if acc then
                    assert FDE_RAMADDR(22)='0' report "FDE address outside unit 0" severity failure;
                    fde_ladr := FDE_RAMADDR; fde_ljob := FDEWR; fde_wd := FDE_RAMWDAT;
                    fde_busy <= '1'; fde_cnt := LAT;
                elsif fde_busy='1' then
                    if fde_cnt > 1 then fde_cnt := fde_cnt - 1;
                    else
                        if fde_ljob='1' then
                            mem.write(to_integer(unsigned(fde_ladr(21 downto 0))), fde_wd);
                        else
                            FDE_RAMRDAT <= mem.read(to_integer(unsigned(fde_ladr(21 downto 0))));
                        end if;
                        fde_busy <= '0';
                    end if;
                end if;
                -- FEC
                acc := fec_busy='0' and ((FEC_WR='1' and (fec_lstb='0' or fec_ladr/=FEC_ADDR or fec_ljob/='1')) or
                                         (FEC_WR='0' and FEC_RD='1' and (fec_lstb='0' or fec_ladr/=FEC_ADDR or fec_ljob/='0')));
                fec_lstb := FEC_WR or FEC_RD;
                if acc then
                    assert FEC_ADDR(22)='0' report "FEC address outside unit 0" severity failure;
                    fec_ladr := FEC_ADDR; fec_ljob := FEC_WR; fec_wd := FEC_WDAT;
                    fec_busy <= '1'; fec_cnt := LAT;
                elsif fec_busy='1' then
                    if fec_cnt > 1 then fec_cnt := fec_cnt - 1;
                    else
                        if fec_ljob='1' then
                            mem.write(to_integer(unsigned(fec_ladr(21 downto 0))), fec_wd);
                        else
                            FEC_RDAT <= mem.read(to_integer(unsigned(fec_ladr(21 downto 0))));
                        end if;
                        fec_busy <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    FDE_RAMWAIT <= fde_busy;
    FEC_RAMWAIT <= fec_busy;

    -------------------------------------------------------------------------
    -- DUT, wired as Zet98MiSTer.vhd (FDT / FD / DISKE / FECC)
    -------------------------------------------------------------------------
    FDT : entity work.FDtiming generic map(SYSFREQ) port map(
        drv0sel=>'0', drv1sel=>'0', drv0sele=>'0', drv1sele=>'0',
        drv0hd=>FDC_H_Dn, drv0hdi=>'1', drv1hd=>FDC_H_Dn, drv1hdi=>'1',
        drv0hds=>open, drv1hds=>open, drv0int=>FDC_int, drv1int=>open,
        hmssft=>FDC_hmssft, clk=>clk, rstn=>rstn);

    fdc_rdn <= cpu_rdn and dma_rdn;
    fdc_ready_in <= FDE_READYn and not FDC_FREADY;
    fdc_motorn <= (not FDC_MOTOR) & (not FDC_MOTOR);
    fdc_tc <= dma_tc;
    FD : entity work.FDC generic map(
        maxtrack=>85, maxbwidth=>(BR_300_D*SYSFREQ/1000000), rdytout=>800,
        preseek=>'0', sysclk=>SYSFREQ/1000)
    port map(
        RDn=>fdc_rdn, WRn=>cpu_wrn, CSn=>cpu_csn, A0=>cpu_a0, WDAT=>cpu_wdat,
        RDAT=>FDC_ODAT, DATOE=>FDC_DOE, DACKn=>dma_dackn, DRQ=>FDC_DRQ,
        TC=>fdc_tc, INTn=>FDC_INTn, WAITIN=>'0',
        WREN=>FDE_WRENn, WRBIT=>FDE_WRBITn, RDBIT=>FDE_RDBITn, STEP=>FDE_STEPn,
        SDIR=>FDE_SDIRn, WPRT=>FDE_WPROTn, track0=>FDE_TRACK0n, index=>FDE_INDEXn,
        side=>FDE_SIDEn, usel=>FDC_USEL,
        READY=>fdc_ready_in,
        int0=>FDC_int, int1=>FDC_int, int2=>FDC_int, int3=>FDC_int,
        td0=>'1', td1=>'1', td2=>'1', td3=>'1',
        hmssft=>FDC_hmssft, busy=>FDC_BUSY, mfm=>FDE_MFM,
        clk=>clk, rstn=>rstn);

    FDC_USELbn <= "1110" when FDC_USEL="00" else "1101" when FDC_USEL="01" else
                  "1011" when FDC_USEL="10" else "1000" when FDC_USEL="11" else "1111";

    DISKE : entity work.diskemu_mister generic map(SYSFREQ, SYSFREQ, 10) port map(
        sasi_din=>(others=>'0'), sasi_dout=>open, sasi_sel=>'0', sasi_bsy=>open,
        sasi_req=>open, sasi_ack=>'0', sasi_io=>open, sasi_cd=>open, sasi_msg=>open,
        sasi_rst=>'0',
        fdc_useln=>FDC_USELbn(1 downto 0), fdc_motorn=>fdc_motorn,
        fdc_readyn=>FDE_READYn, fdc_wrenn=>FDE_WRENn, fdc_wrbitn=>FDE_WRBITn,
        fdc_rdbitn=>FDE_RDBITn, fdc_stepn=>FDE_STEPn, fdc_sdirn=>FDE_SDIRn,
        fdc_track0n=>FDE_TRACK0n, fdc_indexn=>FDE_INDEXn, fdc_siden=>FDE_SIDEn,
        fdc_wprotn=>FDE_WPROTn, fdc_eject=>"00", fdc_indisk=>fdc_indisk,
        fdc_trackwid=>'1', fdc_dencity=>FDC_H_Dn, fdc_rpm=>'0', fdc_mfm=>FDE_MFM,
        fdc_ifmode=>'1',                      -- FDCIF_H_Dn: 1MB interface
        fde_tracklen=>open, fde_ramaddr=>FDE_RAMADDR, fde_ramrdat=>FDE_RAMRDAT,
        fde_ramwdat=>FDE_RAMWDAT, fde_ramwr=>FDE_RAMWR, fde_ramwait=>FDE_RAMWAIT,
        fec_ramaddrh=>FEC_RAMADDRH, fec_ramaddrl=>FEC_RAMADDRL, fec_ramwe=>FEC_RAMWE,
        fec_ramrdat=>FEC_RAMWDAT, fec_ramwdat=>FEC_RAMRDAT, fec_ramrd=>FEC_RAMRD,
        fec_ramwr=>FEC_RAMWR, fec_rambusy=>FEC_RAMBUSY, fec_fdsync=>"00",
        sram_cs=>'0', sram_addr=>(others=>'0'), sram_rdat=>open, sram_wdat=>(others=>'0'),
        sram_rd=>'0', sram_wr=>"00", sram_wp=>'1', sram_ld=>'0', sram_st=>'0',
        mist_mounted=>mist_mounted, mist_readonly=>mist_readonly, mist_imgsize=>mist_imgsize,
        mist_lba=>mist_lba, mist_rd=>mist_rd, mist_wr=>mist_wr, mist_ack=>mist_ack,
        mist_buffaddr=>mist_buffaddr, mist_buffdout=>mist_buffdout,
        mist_buffdin=>mist_buffdin, mist_buffwr=>mist_buffwr,
        initdone=>open, busy=>open, fclk=>clk, sclk=>clk, rclk=>clk, rstn=>rstn);

    FECC : entity work.FECcont generic map(23) port map(
        HIGHADDR=>'0' & FEC_RAMADDRH, BUFADDR=>FEC_RAMADDRL, RD=>FEC_RAMRD,
        WR=>FEC_RAMWR, RDDAT=>FEC_RAMRDAT, WRDAT=>FEC_RAMWDAT, BUFRD=>open,
        BUFWR=>FEC_RAMWE, BUFWAIT=>'0', BUSY=>FEC_RAMBUSY,
        SDR_ADDR=>FEC_ADDR, SDR_RD=>FEC_RD, SDR_WR=>FEC_WR, SDR_RDAT=>FEC_RDAT,
        SDR_WDAT=>FEC_WDAT, SDR_WAIT=>FEC_RAMWAIT, clk=>clk, rstn=>rstn);

    -------------------------------------------------------------------------
    -- 8237 channel 2 model: device-to-memory, one byte per DRQ, TC on last.
    -------------------------------------------------------------------------
    dma : process
        variable last_go : boolean := false;
        variable n : natural := 0;
    begin
        wait until rising_edge(clk);
        if dma_go /= last_go then
            last_go := dma_go;
            n := 0;
            dma_count <= 0;
        end if;
        if FDC_DRQ='1' and n < dma_len then
            dma_dackn <= '0';
            dma_rdn <= '0';
            if n = dma_len-1 then dma_tc <= '1'; end if;
            for i in 1 to 3 loop wait until rising_edge(clk); end loop;
            dmabuf(n) <= to_integer(unsigned(FDC_ODAT));
            n := n + 1;
            dma_count <= n;
            dma_rdn <= '1';
            dma_dackn <= '1';
            dma_tc <= '0';
            wait until rising_edge(clk);
        end if;
    end process;

    -------------------------------------------------------------------------
    -- BIOS-like command sequences
    -------------------------------------------------------------------------
    main : process
        type bytes_t is array(natural range <>) of natural range 0 to 255;
        variable res : bytes_t(0 to 6);
        variable t0 : time;
        variable failures : natural := 0;

        procedure clocks(n : natural) is
        begin
            for i in 1 to n loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure io_write(a0 : std_logic; d : natural) is
        begin
            wait until rising_edge(clk);
            cpu_a0 <= a0; cpu_wdat <= std_logic_vector(to_unsigned(d, 8));
            cpu_csn <= '0'; cpu_wrn <= '0';
            clocks(4);
            cpu_wrn <= '1'; cpu_csn <= '1';
            clocks(4);
        end procedure;

        procedure io_read(a0 : std_logic; d : out natural) is
        begin
            wait until rising_edge(clk);
            cpu_a0 <= a0; cpu_csn <= '0'; cpu_rdn <= '0';
            clocks(3);
            d := to_integer(unsigned(FDC_ODAT));
            cpu_rdn <= '1'; cpu_csn <= '1';
            clocks(4);
        end procedure;

        procedure put(d : natural) is
            variable msr : natural;
            variable tries : natural := 0;
        begin
            loop
                io_read('0', msr);
                exit when (msr / 64) = 2;          -- RQM=1 DIO=0
                tries := tries + 1;
                assert tries < 100000 report "FDC never ready for command byte" severity failure;
            end loop;
            io_write('1', d);
        end procedure;

        procedure get(d : out natural) is
            variable msr : natural;
            variable tries : natural := 0;
        begin
            loop
                io_read('0', msr);
                exit when (msr / 64) = 3;          -- RQM=1 DIO=1
                tries := tries + 1;
                assert tries < 100000 report "FDC never offered result byte" severity failure;
            end loop;
            io_read('1', d);
        end procedure;

        -- wait for INT like FD80:2188; returns elapsed ms
        procedure wait_int(what : string; limit : time; ms : out real) is
        begin
            if FDC_INTn /= '0' then
                wait until FDC_INTn='0' for limit;
            end if;
            ms := real((now - t0) / 1 us) / 1000.0;
            assert FDC_INTn='0' report what & ": no completion interrupt within " &
                time'image(limit) severity failure;
        end procedure;

        procedure sense_int(st0 : out natural; pcn : out natural) is
        begin
            put(16#08#); get(st0); get(pcn);
        end procedure;

        procedure recalibrate is
            variable st0, pcn : natural; variable ms : real;
        begin
            put(16#07#); put(0); t0 := now;
            wait_int("RECALIBRATE", 2 sec, ms);
            sense_int(st0, pcn);
            report "RECALIBRATE ST0=" & integer'image(st0) & " PCN=" & integer'image(pcn);
            assert st0 = 16#20# and pcn = 0 report "recalibrate failed" severity failure;
        end procedure;

        procedure seek(hd, cyl : natural) is
            variable st0, pcn : natural; variable ms : real;
        begin
            put(16#0F#); put(hd*4); put(cyl); t0 := now;
            wait_int("SEEK", 2 sec, ms);
            sense_int(st0, pcn);
            report "SEEK ST0=" & integer'image(st0) & " PCN=" & integer'image(pcn);
            assert pcn = cyl and (st0 / 64) = 0 report "seek failed" severity failure;
        end procedure;

        procedure check_time(what : string; ms : real; limit : natural) is
        begin
            report what & " completed in " & real'image(ms) & " ms";
            if ms > real(limit) then
                report what & " took " & real'image(ms) & " ms, BIOS gives up after " &
                    integer'image(limit) & " ms" severity error;
                failures := failures + 1;
            end if;
        end procedure;

        procedure show(what : string; n : natural) is
            variable s : line;
        begin
            write(s, what & " result:");
            for i in 0 to n-1 loop write(s, string'(" ") & to_hstring(to_unsigned(res(i), 8))); end loop;
            writeline(output, s);
        end procedure;

        procedure read_id(mf, hd : natural; ec, eh, er, en : integer) is
            variable ms : real;
        begin
            put(16#0A# + mf*64); put(hd*4); t0 := now;
            wait_int("READ ID", 3 sec, ms);
            for i in 0 to 6 loop get(res(i)); end loop;
            show("READ ID MF=" & integer'image(mf) & " HD=" & integer'image(hd), 7);
            check_time("READ ID", ms, LIMIT_MS);
            if ec >= 0 then
                if not (res(0) = hd*4 and res(1) = 0 and res(2) = 0 and res(3) = ec and res(4) = eh and
                        (er < 0 or res(5) = er) and res(6) = en) then
                    report "READ ID result mismatch" severity error;
                    failures := failures + 1;
                end if;
            end if;
        end procedure;

        -- READ ID that must fail (wrong density): IC=01, MA.
        procedure read_id_missing(mf, hd : natural) is
            variable ms : real;
        begin
            put(16#0A# + mf*64); put(hd*4); t0 := now;
            wait_int("READ ID (no ID)", 5 sec, ms);
            for i in 0 to 6 loop get(res(i)); end loop;
            show("READ ID MF=" & integer'image(mf) & " HD=" & integer'image(hd) & " (wrong density)", 7);
            check_time("READ ID (no ID)", ms, LIMIT_MS);
            if not (res(0) = 16#40# + hd*4 and (res(1) mod 2) = 1) then
                report "READ ID on wrong density did not report missing address mark" severity error;
                failures := failures + 1;
            end if;
        end procedure;

        procedure read_data(mf, track, hd, c, h, r, n, eot, count : natural) is
            variable ms : real;
            variable size, total, off, bad : natural;
        begin
            size := 128 * 2**n;
            total := size * count;
            dma_len <= total;
            dma_go <= not dma_go;
            wait until rising_edge(clk);
            put(16#06# + mf*64); put(hd*4); put(c); put(h); put(r); put(n);
            put(eot); put(16#1B#); put(16#FF#);
            t0 := now;
            wait_int("READ DATA", 3 sec, ms);
            for i in 0 to 6 loop get(res(i)); end loop;
            show("READ DATA MF=" & integer'image(mf) & " C/H/R/N=" & integer'image(c) & "/" &
                 integer'image(h) & "/" & integer'image(r) & "/" & integer'image(n) & " x" &
                 integer'image(count), 7);
            check_time("READ DATA", ms, LIMIT_MS);
            report "DMA bytes " & integer'image(dma_count) & " of " & integer'image(total);
            if not (res(0) = hd*4 and res(1) = 0 and res(2) = 0) then
                report "READ DATA status error" severity error;
                failures := failures + 1;
            end if;
            if dma_count /= total then
                report "READ DATA transferred " & integer'image(dma_count) & " bytes, expected " &
                    integer'image(total) severity error;
                failures := failures + 1;
            end if;
            bad := 0;
            for k in 0 to count-1 loop
                assert img.find(track, c, h, r+k, n) >= 0 report "sector not in D88" severity failure;
                off := img.find(track, c, h, r+k, n);
                for i in 0 to size-1 loop
                    if dmabuf(k*size+i) /= img.byte(off+i) then
                        if bad < 4 then
                            report "data mismatch sector R=" & integer'image(r+k) & " byte " &
                                integer'image(i) & ": got " & integer'image(dmabuf(k*size+i)) &
                                " expected " & integer'image(img.byte(off+i)) severity error;
                        end if;
                        bad := bad + 1;
                    end if;
                end loop;
            end loop;
            if bad /= 0 then
                report integer'image(bad) & " data bytes differ from the D88" severity error;
                failures := failures + 1;
            end if;
        end procedure;

        -- MT READ DATA from head 0 sector r; count sectors, continuing on head 1
        -- R=1 after EOT (standard R=1..EOT geometry).
        procedure read_data_mt(mf, t0track, c, hd, r, n, eot, count : natural) is
            variable ms : real;
            variable size, total, off, bad, rr, hh : natural;
        begin
            size := 128 * 2**n;
            total := size * count;
            dma_len <= total;
            dma_go <= not dma_go;
            wait until rising_edge(clk);
            put(16#86# + mf*64); put(hd*4); put(c); put(hd); put(r); put(n);
            put(eot); put(16#1B#); put(16#FF#);
            t0 := now;
            wait_int("READ DATA MT", 3 sec, ms);
            for i in 0 to 6 loop get(res(i)); end loop;
            show("READ DATA MT C/H/R/N=" & integer'image(c) & "/" & integer'image(hd) & "/" &
                 integer'image(r) & "/" & integer'image(n) & " x" & integer'image(count), 7);
            check_time("READ DATA MT", ms, LIMIT_MS);
            if not (res(0) / 64 = 0 and res(1) = 0 and res(2) = 0) then
                report "READ DATA MT status error" severity error;
                failures := failures + 1;
            end if;
            if dma_count /= total then
                report "READ DATA MT transferred " & integer'image(dma_count) & " bytes, expected " &
                    integer'image(total) severity error;
                failures := failures + 1;
            end if;
            bad := 0; rr := r; hh := hd;
            for k in 0 to count-1 loop
                assert img.find(t0track + hh, c, hh, rr, n) >= 0 report "sector not in D88" severity failure;
                off := img.find(t0track + hh, c, hh, rr, n);
                for i in 0 to size-1 loop
                    if dmabuf(k*size+i) /= img.byte(off+i) then
                        if bad < 4 then
                            report "data mismatch C/H/R=" & integer'image(c) & "/" & integer'image(hh) &
                                "/" & integer'image(rr) & " byte " & integer'image(i) & ": got " &
                                integer'image(dmabuf(k*size+i)) & " expected " &
                                integer'image(img.byte(off+i)) severity error;
                        end if;
                        bad := bad + 1;
                    end if;
                end loop;
                if rr = eot then rr := 1; hh := 1; else rr := rr + 1; end if;
            end loop;
            if bad /= 0 then
                report integer'image(bad) & " data bytes differ from the D88" severity error;
                failures := failures + 1;
            end if;
        end procedure;

        -- whole cylinder: MT read when both sides are R=1..n with one N,
        -- otherwise one READ DATA per sector ID as stored in the D88
        procedure scan_cylinder(cyl : natural) is
            variable ns, n : natural;
            variable plain : boolean := true;
        begin
            ns := img.nsec(2*cyl);
            n := img.id(2*cyl, 0, 3);
            for h in 0 to 1 loop
                if img.nsec(2*cyl+h) /= ns then plain := false; end if;
                for i in 0 to ns-1 loop
                    if img.nsec(2*cyl+h) = ns then
                        if img.id(2*cyl+h, i, 0) /= cyl or img.id(2*cyl+h, i, 1) /= h or
                           img.id(2*cyl+h, i, 3) /= n then plain := false; end if;
                        for j in 0 to ns-1 loop
                            if img.id(2*cyl+h, j, 2) = i+1 then exit; end if;
                            if j = ns-1 then plain := false; end if;
                        end loop;
                    end if;
                end loop;
            end loop;
            if plain and ns*2*128*2**n <= 16384 then
                read_data_mt(1 - (img.id(2*cyl, 0, 6) / 64) mod 2, 2*cyl, cyl, 0, 1, n, ns, 2*ns);
            else
                for h in 0 to 1 loop
                    for i in 0 to img.nsec(2*cyl+h)-1 loop
                        read_data(1 - (img.id(2*cyl+h, i, 6) / 64) mod 2, 2*cyl+h, h,
                                  img.id(2*cyl+h, i, 0), img.id(2*cyl+h, i, 1), img.id(2*cyl+h, i, 2),
                                  img.id(2*cyl+h, i, 3), img.id(2*cyl+h, i, 2), 1);
                    end loop;
                end loop;
            end if;
        end procedure;

        -- time between two index pulses on head hd of the current cylinder
        procedure index_period(hd : natural) is
            variable ta : time;
            variable ms : real;
        begin
            put(16#04#); put(hd*4); get(res(0));          -- SENSE DRIVE STATUS selects the head
            wait until falling_edge(FDE_INDEXn) for 1 sec;
            ta := now;
            wait until falling_edge(FDE_INDEXn) for 1 sec;
            ms := real((now - ta) / 1 us) / 1000.0;
            report "index period " & real'image(ms) & " ms";
            if ms < 160.0 or ms > 175.0 then
                report "revolution is " & real'image(ms) & " ms, 2HD turns at 360 rpm (166.7 ms)" severity error;
                failures := failures + 1;
            end if;
        end procedure;

        -- Every word of a played revolution must carry the D88 track's density
        -- (bit 9 = MFM): a mixed track overlaps the FM and MFM modulators.
        procedure check_density is
            variable want : std_logic;
            variable bad : natural;
        begin
            for t in 0 to 163 loop
                if img.nsec(t) /= 0 then
                    want := '1';
                    if (img.id(t, 0, 6) / 64) mod 2 = 1 then want := '0'; end if;
                    bad := 0;
                    for i in 0 to 4999 loop    -- FM turn is 5208 words
                        if mem.read(t*16384 + i)(9) /= want then bad := bad + 1; end if;
                    end loop;
                    if bad /= 0 then
                        report "track " & integer'image(t) & ": " & integer'image(bad) &
                            " words of the wrong density" severity error;
                        failures := failures + 1;
                    end if;
                end if;
            end loop;
        end procedure;

        procedure specify is
        begin
            put(16#03#); put(16#C1#); put(16#46#);   -- SRT/HUT, HLT, DMA mode
        end procedure;
    begin
        rstn <= '0';
        clocks(10);
        rstn <= '1';
        wait until fdc_indisk(0)='1' for LOAD_MS * 1 ms;
        assert fdc_indisk(0)='1' report "D88 not loaded after " & integer'image(LOAD_MS) &
            " ms (walked past the 164-entry track table?)" severity failure;
        report "D88 loaded at " & time'image(now);
        clocks(1000);
        check_density;
        specify;
        recalibrate;

        if TEST = "std" then
            read_id(1, 0, 0, 0, -1, 3);
            read_data(1, 0, 0, 0, 0, 1, 3, 8, 2);
            seek(1, 1);
            read_data(1, 3, 1, 1, 1, 7, 3, 8, 2);
            -- the BIOS boot probes FM first: must fail within the timeout
            seek(0, 0);
            read_id_missing(0, 0);
        elsif TEST = "fm" then
            -- a single-density track must still turn at 360 rpm
            index_period(0);
            -- NEC BIOS boot: READ ID MF=0 head 0, then 512 bytes N=0 from R=1
            read_id(0, 0, 0, 0, -1, 0);
            read_data(0, 0, 0, 0, 0, 1, 0, 26, 4);
            -- Xanadu IPL: INT 1Bh AH=16h, 3328 bytes = whole interleaved track
            read_data(0, 0, 0, 0, 0, 1, 0, 26, 26);
            read_data(0, 1, 1, 0, 1, 1, 0, 26, 2);
            -- MFM probe of the FM track: Missing AM within two turns
            read_id_missing(1, 0);
            -- copy-protected MFM track 2 (cyl 1 head 0) with IDs C=0 H=1
            seek(0, 1);
            index_period(0);
            read_id(1, 0, 0, 1, -1, 3);
            read_data(1, 2, 0, 0, 1, 1, 3, 5, 2);
            -- Xanadu's loader then drives the FDC itself and writes port 94h
            -- = 10h / 00h (motor bit clear) around every command; the 1MB
            -- interface's 2HD drive keeps turning (NP2kai ignores the bit)
            FDC_MOTOR <= '0';
            clocks(100);
            for r in 1 to 5 loop
                read_data(1, 2, 0, 0, 1, r, 3, 5, 1);
            end loop;
        elsif TEST = "loh" then
            read_id(1, 0, 0, 0, -1, 3);
            read_data(1, 0, 0, 0, 0, 1, 3, 8, 1);
            -- IPL: INT 1Bh AH=56h R=49 x7 then H=1 R=48 x4, BIOS EOT=8 < R
            read_data(1, 0, 0, 0, 0, 49, 3, 8, 7);
            read_data(1, 1, 1, 0, 1, 48, 3, 8, 4);
            seek(1, 1);
            read_data(1, 3, 1, 1, 1, 53, 3, 8, 3);
        elsif TEST = "scan" then
            for cyl in CYL_FIRST to CYL_LAST loop
                if (cyl - CYL_FIRST) mod CYL_STEP = 0 and img.nsec(2*cyl) /= 0 then
                    seek(0, cyl);
                    scan_cylinder(cyl);
                end if;
            end loop;
        else
            report "unknown TEST " & TEST severity failure;
        end if;

        if failures /= 0 then
            report TEST & ": " & integer'image(failures) & " check(s) failed" severity failure;
        end if;
        report TEST & ": PASS";
        finish;
    end process;
end architecture;
