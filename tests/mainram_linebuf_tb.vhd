library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;
-- mainram_linebuf against a reference memory. The CPU issues random reads
-- and writes (strobe held until acknowledge, like the legacy fabric), a DMA
-- master writes between CPU cycles, and the SDRAM port answers RD1/RD4/WR1
-- after a random latency. Every read must return the reference word.
-- SNOOP=false disconnects write snooping: that must fail on stale data.
-- An EGC stand-in keeps the port after some CPU operations and pulses its
-- own acknowledges, hidden from the CPU (CB_ACK and not EGC_PATH).
-- EGCMASK=false gives the buffer the raw acknowledge: that must fail.
entity mainram_linebuf_tb is
 generic(SNOOP:boolean:=true; EGCMASK:boolean:=true; SEED:positive:=7; OPS:natural:=200000);
end;
architecture test of mainram_linebuf_tb is
 constant AW:integer:=22;
 constant WORDS:integer:=256;           -- small space: frequent group reuse
 type mem_t is array(0 to WORDS-1) of std_logic_vector(15 downto 0);
 signal clk:std_logic:='0';
 signal rstn:std_logic:='0';
 signal elig,mrd,wr,dma:std_logic:='0';
 signal addr:std_logic_vector(AW-1 downto 0):=(others=>'0');
 signal bank:std_logic_vector(1 downto 0):="00";
 signal wdat:std_logic_vector(15 downto 0);
 signal rd1,rd4,sdr_ack,buf_ack,doe,snoop_wr,flush:std_logic:='0';
 signal r0,r1,r2,r3,brdat,cpu_rdat:std_logic_vector(15 downto 0);
 signal cpu_ack,egc,egc_ack,ack_line,buf_sdr_ack,kick:std_logic:='0';
 shared variable mem:mem_t;
begin
 clk<=not clk after 5 ns;
 dut:entity work.mainram_linebuf generic map(AW=>AW) port map(
  elig=>elig,mrd=>mrd,bank=>bank,addr=>addr,
  snoop_wr=>snoop_wr,snoop_bank=>bank,snoop_addr=>addr,flush=>flush,
  sdr_ack=>buf_sdr_ack,sdr_rdat0=>r0,sdr_rdat1=>r1,sdr_rdat2=>r2,sdr_rdat3=>r3,
  rd4=>rd4,ack=>buf_ack,doe=>doe,rdat=>brdat,clk=>clk,rstn=>rstn);
 -- Top-level wiring: eligible reads never use RD1; writes always reach SDRAM.
 rd1<=mrd and not elig;
 snoop_wr<=wr when SNOOP else '0';
 cpu_rdat<=brdat when doe='1' else r0;
 ack_line<=sdr_ack or egc_ack;                  -- the shared CB_ACK
 buf_sdr_ack<=(ack_line and not egc) when EGCMASK else ack_line;
 cpu_ack<=(ack_line and not egc) or buf_ack;
 -- EGC stand-in: after a CPU operation it may keep the port 4..40 clocks,
 -- acknowledging its own four-plane accesses every five clocks.
 egcproc:process
  variable s1,s2:positive:=SEED+200;
  variable x:real;
 begin
  wait until kick='1';
  uniform(s1,s2,x);
  if x<0.3 then
   egc<='1';
   uniform(s1,s2,x);
   for i in 1 to 4+integer(x*36.0) loop
    wait until rising_edge(clk);
    if i mod 5=0 then egc_ack<='1'; else egc_ack<='0'; end if;
   end loop;
   wait until rising_edge(clk); egc_ack<='0'; egc<='0';
  end if;
  wait until kick='0';
 end process;
 -- SDRAM port: a new request (rising edge of any request) completes after
 -- 2..24 clocks with a one-clock acknowledge; posted writes are modelled as
 -- completing in order before any later read.
 sdram:process
  variable s1,s2:positive:=SEED+100;
  variable x:real;
  variable a,b:integer;
 begin
  wait until rising_edge(clk);
  sdr_ack<='0';
  if egc='0' and (rd1='1' or rd4='1' or wr='1') then
   a:=to_integer(unsigned(addr)) mod WORDS;
   if wr='1' then mem(a):=wdat; end if;
   uniform(s1,s2,x);
   for i in 1 to 2+integer(x*22.0) loop wait until rising_edge(clk); end loop;
   b:=a-(a mod 4);
   if rd4='1' then
    r0<=mem(b); r1<=mem(b+1); r2<=mem(b+2); r3<=mem(b+3);
   else
    r0<=mem(a); r1<=(others=>'X'); r2<=(others=>'X'); r3<=(others=>'X');
   end if;
   sdr_ack<='1';
   wait until rising_edge(clk);
   sdr_ack<='0';
   -- wait for the request to drop (the master saw the acknowledge)
   while rd1='1' or rd4='1' or wr='1' loop wait until rising_edge(clk); end loop;
  end if;
 end process;
 cpu:process
  variable s1,s2:positive:=SEED;
  variable x:real;
  variable a:integer;
  variable v:std_logic_vector(15 downto 0);
  variable reads,hits,wd:natural:=0;
 begin
  for i in 0 to WORDS-1 loop mem(i):=std_logic_vector(to_unsigned(i*257,16)); end loop;
  wait for 20 ns; rstn<='1';
  wait until rising_edge(clk);
  for op in 1 to OPS loop
   uniform(s1,s2,x); a:=integer(x*real(WORDS-1));
   -- mostly sequential reads, like copies and code
   if x<0.6 then a:=(reads*1) mod WORDS; end if;
   uniform(s1,s2,x);
   addr<=std_logic_vector(to_unsigned(a,AW));
   if x<0.60 then                                  -- CPU read
    elig<='1'; mrd<='1';
    wd:=0;
    loop wait until rising_edge(clk); wd:=wd+1;
     assert wd<5000 report "deadlock: read never acknowledged at "&integer'image(a) severity failure;
     exit when cpu_ack='1'; end loop;
    assert cpu_rdat=mem(a) report "stale/wrong read at "&integer'image(a)&" op "&integer'image(op) severity failure;
    if buf_ack='1' then hits:=hits+1; end if;
    reads:=reads+1;
    mrd<='0'; elig<='0';
   elsif x<0.85 then                               -- CPU write
    uniform(s1,s2,x); v:=std_logic_vector(to_unsigned(integer(x*65535.0),16));
    wdat<=v; wr<='1';
    loop wait until rising_edge(clk); exit when sdr_ack='1'; end loop;
    wr<='0';
   else                                            -- DMA write (another master)
    uniform(s1,s2,x); v:=std_logic_vector(to_unsigned(integer(x*65535.0),16));
    dma<='1'; wdat<=v; wr<='1';
    loop wait until rising_edge(clk); exit when sdr_ack='1'; end loop;
    wr<='0'; dma<='0';
   end if;
   kick<='1'; wait until rising_edge(clk); kick<='0';
   wait until rising_edge(clk);
  end loop;
  report "PASS main-RAM line buffer: "&integer'image(reads)&" reads, "&integer'image(hits)&" served from the buffer";
  stop; wait;
 end process;
end;
