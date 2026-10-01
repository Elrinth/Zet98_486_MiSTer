-- SPDX-License-Identifier: GPL-3.0-or-later
-- Random CPU (GRCG/EGC) and GDC requests on the block-RAM graphics VRAM,
-- checked against a reference model in completion order, then every
-- touched word is read back through the display port on its own clock.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity gvram_m10k_tb is
generic(SEED : positive := 1; OPS : natural := 3000; BREAK_AFFINE : boolean := false);
end gvram_m10k_tb;

architecture tb of gvram_m10k_tb is
    type model_t is protected
        impure function get(a : natural) return std_logic_vector;
        procedure put(a : natural; d : std_logic_vector(63 downto 0));
    end protected;
    type model_t is protected body
        type mem_t is array(0 to 32767) of std_logic_vector(63 downto 0);
        variable m : mem_t := (others=>(others=>'0'));
        impure function get(a : natural) return std_logic_vector is
        begin return m(a); end function;
        procedure put(a : natural; d : std_logic_vector(63 downto 0)) is
        begin m(a) := d; end procedure;
    end protected body;
    shared variable model : model_t;

    signal clk, vclk : std_logic := '0';
    signal rstn : std_logic := '0';
    type req_a is array(0 to 1) of std_logic_vector(5 downto 0);
    type adr_a is array(0 to 1) of std_logic_vector(16 downto 0);
    type b2_a is array(0 to 1) of std_logic_vector(1 downto 0);
    type b4_a is array(0 to 1) of std_logic_vector(3 downto 0);
    type b16_a is array(0 to 1) of std_logic_vector(15 downto 0);
    type b64_a is array(0 to 1) of std_logic_vector(63 downto 0);
    type bool_a is array(0 to 1) of boolean;
    signal req : req_a := (others=>(others=>'0'));
    signal addr : adr_a := (others=>(others=>'0'));
    signal bsel_s : b2_a := (others=>"11");
    signal psel_s : b4_a := (others=>"1111");
    signal pres_s : b16_a := (others=>(others=>'0'));
    signal wdat_s, xor_s, rdat_s : b64_a := (others=>(others=>'0'));
    signal aff_s : std_logic_vector(0 to 1) := "00";
    signal ack_s : std_logic_vector(0 to 1);
    signal pdone : bool_a := (others=>false);
    signal v_dat : std_logic_vector(63 downto 0);
    signal v_ack : std_logic;
    signal v_page, v_rd : std_logic := '0';
    signal v_addr : std_logic_vector(13 downto 0) := (others=>'0');
    signal done : boolean := false;

    -- Reference result of one operation; updates the model for writes.
    procedure apply(op : natural; a : std_logic_vector(16 downto 0);
                    bsel : std_logic_vector(1 downto 0); psel : std_logic_vector(3 downto 0);
                    pres : std_logic_vector(15 downto 0); wd, xm : std_logic_vector(63 downto 0);
                    aff : std_logic; rd : out std_logic_vector(63 downto 0)) is
        variable w : natural := to_integer(unsigned(a(16 downto 2)));
        variable p : natural := to_integer(unsigned(a(1 downto 0)));
        variable old, nw : std_logic_vector(63 downto 0);
        variable m : std_logic_vector(15 downto 0);
    begin
        old := model.get(w); nw := old; rd := (others=>'0');
        case op is
        when 0 | 4 => -- WR1 / RMW1
            if op=0 then m := wd(15 downto 0); else m := wd(15 downto 0) or (old(p*16+15 downto p*16) and pres); end if;
            if bsel(0)='1' then nw(p*16+7 downto p*16) := m(7 downto 0); end if;
            if bsel(1)='1' then nw(p*16+15 downto p*16+8) := m(15 downto 8); end if;
        when 1 | 5 => -- WR4 / RMW4
            for i in 0 to 3 loop
                if op=1 then m := wd(i*16+15 downto i*16);
                elsif aff='1' then m := wd(i*16+15 downto i*16) xor (old(i*16+15 downto i*16) and xm(i*16+15 downto i*16));
                else m := wd(i*16+15 downto i*16) or (old(i*16+15 downto i*16) and pres); end if;
                if psel(i)='1' and bsel(0)='1' then nw(i*16+7 downto i*16) := m(7 downto 0); end if;
                if psel(i)='1' and bsel(1)='1' then nw(i*16+15 downto i*16+8) := m(15 downto 8); end if;
            end loop;
        when 2 => rd := x"000000000000" & old(p*16+15 downto p*16);
        when others => rd := old;
        end case;
        model.put(w, nw);
    end procedure;
begin
    clk <= not clk after 5555 ps when not done else '0';
    vclk <= not vclk after 23333 ps when not done else '0';

    dut : entity work.gvram_m10k port map(
        clk=>clk, rstn=>rstn,
        c_wr1=>req(0)(0), c_wr4=>req(0)(1), c_rd1=>req(0)(2), c_rd4=>req(0)(3), c_rmw1=>req(0)(4), c_rmw4=>req(0)(5),
        c_addr=>addr(0), c_bsel=>bsel_s(0), c_psel=>psel_s(0), c_preserve=>pres_s(0), c_wdat=>wdat_s(0),
        c_affine=>aff_s(0), c_xormask=>xor_s(0), c_rdat=>rdat_s(0), c_ack=>ack_s(0),
        s_wr1=>req(1)(0), s_wr4=>req(1)(1), s_rd1=>req(1)(2), s_rd4=>req(1)(3), s_rmw1=>req(1)(4), s_rmw4=>req(1)(5),
        s_addr=>addr(1), s_bsel=>bsel_s(1), s_psel=>psel_s(1), s_preserve=>pres_s(1), s_wdat=>wdat_s(1),
        s_rdat=>rdat_s(1), s_ack=>ack_s(1),
        vclk=>vclk, vrstn=>rstn, v_page=>v_page, v_addr=>v_addr, v_rd=>v_rd, v_ack=>v_ack, v_dat=>v_dat);

    port_gen : for k in 0 to 1 generate
        process
            variable s1, s2 : positive;
            variable r : real;
            variable op, gap, lastop : natural;
            variable a, la : std_logic_vector(16 downto 0);
            variable bsel : std_logic_vector(1 downto 0);
            variable psel : std_logic_vector(3 downto 0);
            variable pres : std_logic_vector(15 downto 0);
            variable wd, xm, exp, got : std_logic_vector(63 downto 0);
            variable aff : std_logic;
            variable held : boolean := false;
            impure function rnd(n : natural) return natural is
            begin uniform(s1, s2, r); return natural(floor(r*real(n))) mod n; end function;
            impure function rv(n : natural) return std_logic_vector is
                variable v : std_logic_vector(n-1 downto 0);
            begin for i in 0 to n-1 loop if rnd(2)=1 then v(i):='1'; else v(i):='0'; end if; end loop; return v; end function;
            procedure drive(o : natural; lvl : std_logic) is
                variable v : std_logic_vector(5 downto 0) := (others=>'0');
            begin
                if lvl='1' then v(o) := '1'; end if;
                req(k) <= v;
            end procedure;
        begin
            s1 := SEED*7+k*13+1; s2 := SEED*3+k*5+2;
            la := (others=>'1');
            wait until rstn='1';
            for n in 1 to OPS loop
                op := rnd(6);
                -- Operation encoding of drive(): 0 WR1, 1 WR4, 2 RD1, 3 RD4, 4 RMW1, 5 RMW4
                if rnd(8)=0 then a := rv(17);
                else a := rv(1) & "0000000000" & rv(4) & rv(2); end if;
                if held and a=la then a(0) := not a(0); end if;
                bsel := rv(2); psel := rv(4); pres := rv(16); wd := rv(64); xm := rv(64);
                if k=0 then aff := rv(1)(0); else aff := '0'; end if;
                addr(k)<=a; bsel_s(k)<=bsel; psel_s(k)<=psel; pres_s(k)<=pres;
                wdat_s(k)<=wd; xor_s(k)<=xm; aff_s(k)<=aff;
                drive(op, '1');
                loop
                    wait until rising_edge(clk);
                    exit when ack_s(k)='1';
                end loop;
                got := rdat_s(k);
                if BREAK_AFFINE and op=5 and aff='1' then aff := '0'; end if;
                if op/=5 then aff := '0'; end if;
                apply(op, a, bsel, psel, pres, wd, xm, aff, exp);
                if op=2 or op=3 then
                    assert got=exp report "port " & integer'image(k) & " read mismatch at op " & integer'image(n) & " kind " & integer'image(op) & " addr " & to_hstring(a) & " exp " & to_hstring(exp) & " got " & to_hstring(got) severity failure;
                end if;
                la := a;
                gap := rnd(4);
                if gap=0 then
                    held := true;          -- next request changes address while held
                else
                    held := false; drive(0, '0');
                    for g in 1 to gap loop wait until rising_edge(clk); end loop;
                end if;
            end loop;
            drive(0, '0');
            pdone(k) <= true;
            wait;
        end process;
    end generate;

    process
        variable exp : std_logic_vector(63 downto 0);
    begin
        rstn <= '0';
        for i in 1 to 5 loop wait until rising_edge(vclk); end loop;
        rstn <= '1';
        wait until pdone(0) and pdone(1);
        for pg in 0 to 1 loop
            if pg=1 then v_page <= '1'; else v_page <= '0'; end if;
            for i in 1 to 3 loop wait until rising_edge(vclk); end loop;
            for w in 0 to 15 loop
                v_addr <= std_logic_vector(to_unsigned(w, 14));
                v_rd <= '1';
                wait until rising_edge(vclk) and v_ack='1';
                exp := model.get(pg*16384 + w);
                assert v_dat=exp report "display read mismatch page " & integer'image(pg) &
                    " word " & integer'image(w) severity failure;
                v_rd <= '0';
                wait until rising_edge(vclk) and v_ack='0';
            end loop;
        end loop;
        report "PASS gvram_m10k seed " & integer'image(SEED);
        done <= true;
        wait;
    end process;
end tb;
