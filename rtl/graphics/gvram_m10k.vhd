-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 16-colour plane graphics VRAM in block RAM: 2 pages x 16K words x 4
-- planes (B,R,G,E), one 64-bit word per address, so a four-plane GRCG,
-- EGC or GDC access is a single RAM cycle instead of an SDRAM burst.
-- Word address bits as the SDRAM layout they replace: addr(16) page,
-- addr(15:2) word, addr(1:0) plane of a single-plane access.
--
-- CPU (GRCG/EGC) and GDC drawing requests keep the SDRAMC held-request
-- contract: a request is new when it rises or its address changes, and
-- completes with a one-cycle acknowledge with read words registered on the
-- same edge. Writes are acknowledged when accepted (posted). Merges match SDRAMC: RMW writes wdat or (old and preserve);
-- EGC affine RMW4 writes wdat xor (old and mask). WR1/WR4 write wdat.
-- The display reads 64-bit words on its own clock (held read, level ACK).
entity gvram_m10k is
port(
    clk         : in std_logic;
    rstn        : in std_logic;

    c_wr1, c_wr4, c_rd1, c_rd4, c_rmw1, c_rmw4 : in std_logic;
    c_addr      : in std_logic_vector(16 downto 0);
    c_bsel      : in std_logic_vector(1 downto 0);
    c_psel      : in std_logic_vector(3 downto 0);
    c_preserve  : in std_logic_vector(15 downto 0);
    c_wdat      : in std_logic_vector(63 downto 0);
    c_affine    : in std_logic;
    c_xormask   : in std_logic_vector(63 downto 0);
    c_rdat      : out std_logic_vector(63 downto 0);
    c_ack       : out std_logic;

    s_wr1, s_wr4, s_rd1, s_rd4, s_rmw1, s_rmw4 : in std_logic;
    s_addr      : in std_logic_vector(16 downto 0);
    s_bsel      : in std_logic_vector(1 downto 0);
    s_psel      : in std_logic_vector(3 downto 0);
    s_preserve  : in std_logic_vector(15 downto 0);
    s_wdat      : in std_logic_vector(63 downto 0);
    s_rdat      : out std_logic_vector(63 downto 0);
    s_ack       : out std_logic;

    vclk        : in std_logic;
    vrstn       : in std_logic;
    v_page      : in std_logic;
    v_addr      : in std_logic_vector(13 downto 0);
    v_rd        : in std_logic;
    v_ack       : out std_logic;
    v_dat       : out std_logic_vector(63 downto 0)
);
end gvram_m10k;

architecture rtl of gvram_m10k is
    type op_t is (OP_WR1, OP_WR4, OP_RD1, OP_RD4, OP_RMW1, OP_RMW4);
    type st_t is (ST_IDLE, ST_READ, ST_MERGE);
    signal st : st_t;
    signal c_any, s_any, c_new, s_new : std_logic;
    signal c_stb, s_stb, last_sub : std_logic;
    signal c_laddr, s_laddr : std_logic_vector(16 downto 0);

    signal op : op_t;
    signal op_sub, op_affine : std_logic;
    signal op_addr : std_logic_vector(16 downto 0);
    signal op_bsel : std_logic_vector(1 downto 0);
    signal op_psel : std_logic_vector(3 downto 0);
    signal op_preserve : std_logic_vector(15 downto 0);
    signal op_wdat, op_xor : std_logic_vector(63 downto 0);

    signal ram_we : std_logic_vector(7 downto 0);
    signal ram_wdat, ram_q, vram_q : std_logic_vector(63 downto 0);

    signal page_sync : std_logic_vector(1 downto 0);
    attribute altera_attribute : string;
    attribute altera_attribute of page_sync : signal is
        "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
    signal v_stb : std_logic;
    signal v_phase : integer range 0 to 2;
    signal v_raddr : std_logic_vector(14 downto 0);

    function op_of(wr1, wr4, rd1, rd4, rmw1 : std_logic) return op_t is
    begin
        if wr1='1' then return OP_WR1;
        elsif wr4='1' then return OP_WR4;
        elsif rd1='1' then return OP_RD1;
        elsif rd4='1' then return OP_RD4;
        elsif rmw1='1' then return OP_RMW1;
        else return OP_RMW4;
        end if;
    end function;
begin
    c_any <= c_wr1 or c_wr4 or c_rd1 or c_rd4 or c_rmw1 or c_rmw4;
    s_any <= s_wr1 or s_wr4 or s_rd1 or s_rd4 or s_rmw1 or s_rmw4;
    c_new <= c_any when c_stb='0' or c_laddr/=c_addr else '0';
    s_new <= s_any when s_stb='0' or s_laddr/=s_addr else '0';

    process(clk, rstn)
        variable p : integer range 0 to 3;
        variable old, merged : std_logic_vector(15 downto 0);
    begin
        if rstn='0' then
            st <= ST_IDLE; c_stb <= '0'; s_stb <= '0'; last_sub <= '0';
            c_ack <= '0'; s_ack <= '0'; ram_we <= (others=>'0');
            c_rdat <= (others=>'0'); s_rdat <= (others=>'0');
            ram_wdat <= (others=>'0');
            op <= OP_RD1; op_sub <= '0'; op_affine <= '0';
            op_addr <= (others=>'0'); op_bsel <= "00"; op_psel <= "0000";
            op_preserve <= (others=>'0');
            op_wdat <= (others=>'0'); op_xor <= (others=>'0');
            c_laddr <= (others=>'0'); s_laddr <= (others=>'0');
        elsif rising_edge(clk) then
            c_ack <= '0'; s_ack <= '0'; ram_we <= (others=>'0');
            if c_any='0' then c_stb <= '0'; end if;
            if s_any='0' then s_stb <= '0'; end if;
            case st is
            when ST_IDLE =>
                -- Alternate when both wait, as the SDRAMC CPU/SUB scheduler.
                if s_new='1' and (c_new='0' or last_sub='0') then
                    s_stb <= '1'; s_laddr <= s_addr; last_sub <= '1';
                    op <= op_of(s_wr1, s_wr4, s_rd1, s_rd4, s_rmw1);
                    op_sub <= '1'; op_affine <= '0';
                    op_addr <= s_addr; op_bsel <= s_bsel; op_psel <= s_psel;
                    op_preserve <= s_preserve; op_wdat <= s_wdat;
                    op_xor <= (others=>'0');
                    -- Writes are posted: acknowledged on acceptance and
                    -- finished in the next three cycles, before any later
                    -- request reaches the RAM (one operation at a time).
                    s_ack <= not (s_rd1 or s_rd4);
                    st <= ST_READ;
                elsif c_new='1' then
                    c_stb <= '1'; c_laddr <= c_addr; last_sub <= '0';
                    op <= op_of(c_wr1, c_wr4, c_rd1, c_rd4, c_rmw1);
                    op_sub <= '0'; op_affine <= c_affine and c_rmw4;
                    op_addr <= c_addr; op_bsel <= c_bsel; op_psel <= c_psel;
                    op_preserve <= c_preserve; op_wdat <= c_wdat;
                    op_xor <= c_xormask;
                    c_ack <= not (c_rd1 or c_rd4);
                    st <= ST_READ;
                end if;
            when ST_READ =>
                -- The block RAM registers op_addr on this edge.
                st <= ST_MERGE;
            when ST_MERGE =>
                p := to_integer(unsigned(op_addr(1 downto 0)));
                case op is
                when OP_RD1 =>
                    old := ram_q(p*16+15 downto p*16);
                    if op_sub='1' then s_rdat <= x"000000000000" & old;
                    else c_rdat <= x"000000000000" & old; end if;
                when OP_RD4 =>
                    if op_sub='1' then s_rdat <= ram_q; else c_rdat <= ram_q; end if;
                when OP_WR1 | OP_RMW1 =>
                    old := ram_q(p*16+15 downto p*16);
                    if op = OP_WR1 then merged := op_wdat(15 downto 0);
                    else merged := op_wdat(15 downto 0) or (old and op_preserve); end if;
                    for i in 0 to 3 loop
                        ram_wdat(i*16+15 downto i*16) <= merged;
                    end loop;
                    ram_we(p*2) <= op_bsel(0);
                    ram_we(p*2+1) <= op_bsel(1);
                when OP_WR4 | OP_RMW4 =>
                    for i in 0 to 3 loop
                        old := ram_q(i*16+15 downto i*16);
                        if op = OP_WR4 then
                            merged := op_wdat(i*16+15 downto i*16);
                        elsif op_affine='1' then
                            merged := op_wdat(i*16+15 downto i*16) xor
                                      (old and op_xor(i*16+15 downto i*16));
                        else
                            merged := op_wdat(i*16+15 downto i*16) or (old and op_preserve);
                        end if;
                        ram_wdat(i*16+15 downto i*16) <= merged;
                        ram_we(i*2) <= op_psel(i) and op_bsel(0);
                        ram_we(i*2+1) <= op_psel(i) and op_bsel(1);
                    end loop;
                end case;
                -- Reads complete here. A write lands on the next edge with
                -- this op_addr, before the next request reaches the RAM.
                if op=OP_RD1 or op=OP_RD4 then
                    if op_sub='1' then s_ack <= '1'; else c_ack <= '1'; end if;
                end if;
                st <= ST_IDLE;
            end case;
        end if;
    end process;

    process(vclk, vrstn) begin
        if vrstn='0' then
            page_sync <= "00"; v_stb <= '0'; v_ack <= '0'; v_phase <= 0;
            v_raddr <= (others=>'0');
        elsif rising_edge(vclk) then
            page_sync <= page_sync(0) & v_page;
            if v_rd='0' then
                v_stb <= '0'; v_ack <= '0'; v_phase <= 0;
            elsif v_stb='0' then
                v_stb <= '1'; v_phase <= 1;
                v_raddr <= page_sync(1) & v_addr;
            elsif v_phase=1 then
                v_phase <= 2;
            elsif v_phase=2 then
                v_ack <= '1'; v_phase <= 0;
            end if;
        end if;
    end process;

    -- The display holds v_rd (and so v_raddr) until it has taken the data;
    -- port B re-reads the held address each edge, so its output is stable.
    v_dat <= vram_q;

    mem : entity work.gvram_m10k_lanes port map(
        clk_a=>clk, addr_a=>op_addr(16 downto 2), we_a=>ram_we, d_a=>ram_wdat, q_a=>ram_q,
        clk_b=>vclk, addr_b=>v_raddr, q_b=>vram_q);
end rtl;
