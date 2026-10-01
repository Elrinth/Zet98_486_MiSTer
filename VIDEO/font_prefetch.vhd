-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.VIDEO_TIMING_pkg.all;

-- Kanji/ANK font from SDRAM for the text renderer (KNJSCR), one text row
-- ahead. FONT.ROM banks 0 and 1 are already in SDRAM (the boot loader
-- writes boot.rom there); bank 2 (user-defined characters) stays in block
-- RAM and is read live by the renderer.
--
-- For each row, during horizontal blanking (units SCAN_FIRST..SCAN_LAST,
-- while the renderer leaves text RAM alone) the 80 character codes of the
-- next row are read and turned into glyph addresses with the renderer's
-- own rules (two-cell Kanji halves, alternating user-defined halves), into
-- a queue. Each glyph (16 bytes) is then read as two 4-word SDRAM bursts
-- into a double-buffered glyph RAM, which the renderer reads by cell and
-- line. Row 0 and row 1 are fetched in vertical blanking; row r+1 when the
-- renderer starts row r. Text changed after its row was fetched shows on
-- the next frame.
entity font_prefetch is
generic(
    SCAN_FIRST : integer := 2;
    SCAN_LAST  : integer := 25
);
port(
    clk     : in std_logic;
    rstn    : in std_logic;
    -- renderer timing (pixel clock)
    HUCOUNT : in integer range 0 to (HWIDTH/DOTPU)-1;
    VCOUNT  : in integer range 0 to VWIDTH-1;
    HCOMP   : in std_logic;
    DHCOMP  : in std_logic;
    DVCOMP  : in std_logic;
    C_LIN   : in integer range 0 to 31;
    BASEADDR: in std_logic_vector(12 downto 0);
    PITCH   : in std_logic_vector(12 downto 0);
    -- text RAM read port, borrowed during the scan window
    TRAMADR : out std_logic_vector(12 downto 0);
    TRAMDRV : out std_logic;
    TRAMDAT : in std_logic_vector(15 downto 0);
    -- renderer glyph read: cell of the row and line in the glyph
    RD_CELL : in std_logic_vector(6 downto 0);
    RD_LINE : in std_logic_vector(3 downto 0);
    RD_BYTE : out std_logic_vector(7 downto 0);
    -- SDRAM font reads: word address in FONT.ROM (bank & byte(16:1)),
    -- four words per held request
    FNTADR  : out std_logic_vector(16 downto 0);
    FNTRD   : out std_logic;
    FNTACK  : in std_logic;
    FNTDAT  : in std_logic_vector(63 downto 0)
);
end font_prefetch;

architecture rtl of font_prefetch is
    constant CELLS : integer := 80;
    -- KNJSCR two-cell Kanji test (the left half retains its code for the
    -- right cell); keep in step with KNJSCR.iskanji.
    function iskanji(t : std_logic_vector(15 downto 0)) return std_logic is
    begin
        if t(15 downto 8)=x"00" then return '0'; end if;
        case t(7 downto 0) is
        when x"01" | x"02" | x"03" | x"04" | x"05" | x"06" | x"07" | x"0d" |
             x"50" | x"51" | x"52" | x"53" | x"54" | x"55" => return '1';
        when others => null;
        end case;
        case t(7 downto 4) is
        when x"1" | x"2" | x"3" | x"4" => return '1';
        when others => return '0';
        end case;
    end function;

    signal disp_side : std_logic;
    signal row_addr : std_logic_vector(12 downto 0);
    signal trig : std_logic;
    signal trig_side : std_logic;
    signal trig_addr : std_logic_vector(12 downto 0);

    signal scan_pending, scan_side, drv : std_logic;
    signal scan_base, scan_addr : std_logic_vector(12 downto 0);
    signal issue_idx : integer range 0 to CELLS;
    signal v1, v2 : std_logic;
    signal i1, i2 : integer range 0 to CELLS-1;
    signal ret, gaiji_r : std_logic;
    signal ret_code, kcode : std_logic_vector(15 downto 0);
    signal force_k : std_logic;
    signal romsel : std_logic_vector(1 downto 0);
    signal romaddr : std_logic_vector(16 downto 0);

    type q_t is array(0 to 255) of std_logic_vector(15 downto 0);
    signal qram : q_t;
    signal q_we : std_logic;
    signal q_waddr, q_raddr : std_logic_vector(7 downto 0);
    signal q_wdat, q_out : std_logic_vector(15 downto 0);

    type g_t is array(0 to 511) of std_logic_vector(63 downto 0);
    signal gram : g_t;
    signal g_we : std_logic;
    signal g_waddr, g_raddr : std_logic_vector(8 downto 0);
    signal g_out : std_logic_vector(63 downto 0);

    type f_t is (F_IDLE, F_QREAD, F_QWAIT, F_QUSE, F_REQ, F_LOW);
    signal fst : f_t;
    signal f_go, f_side : std_logic;
    signal f_adr : std_logic_vector(16 downto 0);
    signal f_dat : std_logic_vector(63 downto 0);
    signal f_rd : std_logic;
    signal f_cell : integer range 0 to CELLS;
begin
    -- Row bookkeeping, mirroring KNJSCR: the frame base is taken at the
    -- frame start, and the renderer advances a row at the delayed line start
    -- after the first visible line when the line in the row returns to 0.
    process(clk, rstn)
        variable next_addr : std_logic_vector(12 downto 0);
    begin
        if rstn='0' then
            disp_side <= '0'; trig <= '0'; trig_side <= '0';
            trig_addr <= (others=>'0'); row_addr <= (others=>'0');
        elsif rising_edge(clk) then
            trig <= '0';
            if DVCOMP='1' then
                disp_side <= '0';
                row_addr <= BASEADDR;
            end if;
            if HCOMP='1' and VCOUNT=VIV-8 then
                trig <= '1'; trig_side <= '0'; trig_addr <= row_addr;
            end if;
            if HCOMP='1' and VCOUNT=VIV-4 then
                next_addr := row_addr + PITCH;
                trig <= '1'; trig_side <= '1'; trig_addr <= next_addr;
                row_addr <= next_addr;
            end if;
            if DHCOMP='1' and VCOUNT>VIV and C_LIN=0 then
                next_addr := row_addr + PITCH;
                disp_side <= not disp_side;
                trig <= '1'; trig_side <= disp_side; trig_addr <= next_addr;
                row_addr <= next_addr;
            end if;
        end if;
    end process;

    -- Next-row code scan in horizontal blanking, with the KNJSCR cell rules.
    kcode <= ret_code when ret='1' else
             gaiji_r & TRAMDAT(14 downto 8) & '0' & TRAMDAT(6 downto 0)
                 when TRAMDAT(15 downto 8)/=x"00" and TRAMDAT(6 downto 1)="101011" else
             TRAMDAT;
    force_k <= '1' when ret='0' and TRAMDAT(15 downto 8)/=x"00" and TRAMDAT(6 downto 1)="101011" else '0';
    acnv : entity work.knjaddrcnv port map(
        kcode=>kcode, cline=>"0000", force_kanji=>force_k,
        mon=>open, romsel=>romsel, romaddr=>romaddr);

    FNTADR <= f_adr;
    FNTRD <= f_rd;
    TRAMADR <= scan_addr;
    TRAMDRV <= drv;

    process(clk, rstn)
        variable isg : std_logic;
    begin
        if rstn='0' then
            scan_pending <= '0'; scan_side <= '0'; drv <= '0';
            scan_base <= (others=>'0'); scan_addr <= (others=>'0');
            issue_idx <= 0; v1 <= '0'; v2 <= '0'; i1 <= 0; i2 <= 0;
            ret <= '0'; gaiji_r <= '0'; ret_code <= (others=>'0');
            q_we <= '0'; q_waddr <= (others=>'0'); q_wdat <= (others=>'0');
            f_go <= '0';
        elsif rising_edge(clk) then
            q_we <= '0'; f_go <= '0';
            v2 <= v1; i2 <= i1;
            if trig='1' then
                scan_pending <= '1'; scan_side <= trig_side; scan_base <= trig_addr;
                issue_idx <= 0; ret <= '0'; gaiji_r <= '0';
                drv <= '0'; v1 <= '0'; v2 <= '0';
            else
                if scan_pending='1' and issue_idx<CELLS and
                   HUCOUNT>=SCAN_FIRST and HUCOUNT<=SCAN_LAST then
                    scan_addr <= scan_base + conv_std_logic_vector(issue_idx, 13);
                    drv <= '1'; v1 <= '1'; i1 <= issue_idx;
                    issue_idx <= issue_idx + 1;
                else
                    drv <= '0'; v1 <= '0';
                end if;
                if v2='1' then
                    -- Text RAM data for the address issued two edges ago.
                    isg := '0';
                    if TRAMDAT(15 downto 8)/=x"00" and TRAMDAT(6 downto 1)="101011" then
                        isg := '1';
                    end if;
                    if ret='1' then
                        ret <= '0';
                    else
                        if iskanji(TRAMDAT)='1' and TRAMDAT(15)='0' then
                            ret <= '1'; ret_code <= '1' & TRAMDAT(14 downto 0);
                        end if;
                        if isg='1' then gaiji_r <= not gaiji_r; else gaiji_r <= '0'; end if;
                    end if;
                    q_we <= '1';
                    q_waddr <= scan_side & conv_std_logic_vector(i2, 7);
                    q_wdat <= (not romsel(1)) & romsel(0) & romaddr(16 downto 4) & '0';
                    if i2=CELLS-1 then
                        scan_pending <= '0'; f_go <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Glyph-address queue: side & cell.
    process(clk) begin
        if rising_edge(clk) then
            if q_we='1' then qram(conv_integer(q_waddr)) <= q_wdat; end if;
            q_out <= qram(conv_integer(q_raddr));
        end if;
    end process;

    -- Glyph buffer: side & cell & half (lines 0-7, 8-15); byte = line(2:0).
    g_raddr <= disp_side & RD_CELL & RD_LINE(3);
    process(clk) begin
        if rising_edge(clk) then
            if g_we='1' then gram(conv_integer(g_waddr)) <= f_dat; end if;
            g_out <= gram(conv_integer(g_raddr));
        end if;
    end process;
    with RD_LINE(2 downto 0) select RD_BYTE <=
        g_out(7 downto 0)   when "000", g_out(15 downto 8)  when "001",
        g_out(23 downto 16) when "010", g_out(31 downto 24) when "011",
        g_out(39 downto 32) when "100", g_out(47 downto 40) when "101",
        g_out(55 downto 48) when "110", g_out(63 downto 56) when others;

    -- SDRAM fetch. A held read is never withdrawn before its acknowledge;
    -- rows queue one deep; one late enough to need its own side again is
    -- abandoned at the next request boundary.
    process(clk, rstn)
        variable f_pend, f_abort, f_pside : std_logic;
    begin
        if rstn='0' then
            fst <= F_IDLE; f_rd <= '0'; f_adr <= (others=>'0');
            f_side <= '0'; f_cell <= 0;
            g_we <= '0'; g_waddr <= (others=>'0'); q_raddr <= (others=>'0');
            f_dat <= (others=>'0');
            f_pend := '0'; f_abort := '0'; f_pside := '0';
        elsif rising_edge(clk) then
            g_we <= '0';
            -- A new row only abandons a fetch still filling that same side.
            if trig='1' and fst/=F_IDLE and trig_side=f_side then f_abort := '1'; end if;
            if f_go='1' then f_pend := '1'; f_pside := scan_side; end if;
            case fst is
            when F_IDLE =>
                f_abort := '0';
                if f_pend='1' then
                    f_pend := '0'; f_side <= f_pside; f_cell <= 0;
                    fst <= F_QREAD;
                end if;
            when F_QREAD =>
                q_raddr <= f_side & conv_std_logic_vector(f_cell, 7);
                fst <= F_QWAIT;
                if f_abort='1' then fst <= F_IDLE; end if;
            when F_QWAIT =>
                -- q_out updates on this edge.
                fst <= F_QUSE;
                if f_abort='1' then fst <= F_IDLE; end if;
            when F_QUSE =>
                if q_out(15)='1' and f_abort='0' then
                    f_adr <= q_out(14 downto 1) & "000"; f_rd <= '1'; fst <= F_REQ;
                elsif f_cell=CELLS-1 or f_abort='1' then
                    fst <= F_IDLE;
                else
                    f_cell <= f_cell+1; fst <= F_QREAD;
                end if;
            when F_REQ =>
                if FNTACK='1' then
                    -- Completed-read capture (bundled SDRAM data crossing,
                    -- see pc98-graphics-transfer.sdc); the RAM writes it next.
                    f_dat <= FNTDAT;
                    g_we <= '1';
                    g_waddr <= f_side & conv_std_logic_vector(f_cell, 7) & f_adr(2);
                    f_rd <= '0'; fst <= F_LOW;
                end if;
            when F_LOW =>
                if FNTACK='0' then
                    if f_abort='1' then
                        fst <= F_IDLE;
                    elsif f_adr(2)='0' then
                        f_adr(2) <= '1'; f_rd <= '1'; fst <= F_REQ;
                    elsif f_cell=CELLS-1 then
                        fst <= F_IDLE;
                    else
                        f_cell <= f_cell+1; fst <= F_QREAD;
                    end if;
                end if;
            end case;
        end if;
    end process;
end rtl;
