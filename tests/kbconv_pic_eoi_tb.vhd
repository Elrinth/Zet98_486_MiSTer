-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual KBCONV + z8259. Reuse the byte adapter/table models from the
-- converter transport test. No CPU or game binary is involved.
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity kbconv_pic_eoi_tb is generic(EOI_DELAY:natural:=64; ACK_CYCLES:positive:=1);end;
architecture test of kbconv_pic_eoi_tb is
 signal clk:std_logic:='0';signal rstn:std_logic:='0';
 signal kcs,kaddr,krd:std_logic:='0';
 signal data:std_logic_vector(7 downto 0);
 signal kirq,kco,kdo:std_logic;signal kci,kdi:std_logic:='1';
 signal pcs,pa,pwr,inta:std_logic:='0';
 signal pdin,pdout:std_logic_vector(7 downto 0):=x"00";
 signal irq:std_logic;
begin
 clk<=not clk after 25 ns;
 kb:entity work.KBCONV generic map(CLKCYC=>20000,SFTCYC=>400,RPSET=>0)
 port map(CS=>kcs,ADDR=>kaddr,RD=>krd,WR=>'0',RDAT=>data,WDAT=>x"00",OE=>open,INT=>kirq,
 KBCLKIN=>kci,KBCLKOUT=>kco,KBDATIN=>kdi,KBDATOUT=>kdo,emuen=>'0',emurx=>open,
 emurxdat=>open,monout=>open,clk=>clk,rstn=>rstn);
 pic:entity work.z8259 port map(CS=>pcs,ADDR=>pa,DIN=>pdin,DOUT=>pdout,DOE=>open,RD=>'1',WR=>pwr,
 IR0=>'0',IR1=>kirq,IR2=>'0',IR3=>'0',IR4=>'0',IR5=>'0',IR6=>'0',IR7=>'0',
 INT=>irq,INTA=>inta,CASI=>"000",CASO=>open,CASM=>'1',clk=>clk,rstn=>rstn);
 process
  procedure cycles(n:natural) is begin for i in 1 to n loop wait until falling_edge(clk);end loop;end;
  procedure command(a:std_logic;b:std_logic_vector(7 downto 0)) is begin
   pcs<='1';pa<=a;pdin<=b;pwr<='1';cycles(3);pwr<='0';pcs<='0';cycles(8);
  end;
  procedure send_byte(b:std_logic_vector(7 downto 0)) is begin
   for i in 0 to 7 loop kdi<=b(i);kci<='1';cycles(3);kci<='0';cycles(3);end loop;
   kci<='1';cycles(3200);
  end;
  procedure service(expected:std_logic_vector(7 downto 0);delay_eoi:natural) is begin
   for i in 1 to 100 loop exit when irq='1';cycles(1);end loop;
   assert irq='1' report "PIC lost queued keyboard interrupt before EOI" severity failure;
   inta<='1';wait for 1 ns;
   assert pdout=x"09" report "wrong keyboard vector" severity failure;
   for i in 1 to ACK_CYCLES loop
    cycles(1);wait for 1 ns;assert pdout=x"09" report "vector changed during acknowledge" severity failure;
   end loop;inta<='0';cycles(12);
   command('0',x"0a");pa<='0';cycles(2);
   assert pdout(1)='0' report "accepted request remained in IRR after INTA" severity failure;
   kcs<='1';kaddr<='0';krd<='1';cycles(3);
   assert data=expected report "wrong keyboard byte" severity failure;
   krd<='0';kcs<='0';cycles(delay_eoi);
   report "before EOI, next keyboard RXRDY=" & std_logic'image(kirq);
   command('0',x"20");cycles(20);
  end;
 begin
  cycles(4);rstn<='1';cycles(4);
  command('0',x"13");command('1',x"08");command('1',x"0d");command('1',x"fd");
  cycles(30000);
  -- A make and its break arrive while the guest is busy. The converter
  -- publishes the break soon after the handler reads the make, before EOI.
  send_byte(x"76");send_byte(x"F0");send_byte(x"76");
  service(x"00",EOI_DELAY);
  assert kirq='1' report "converter failed to retain release" severity failure;
  service(x"80",EOI_DELAY);
  assert irq='0' and kirq='0' report "interrupt repeated after final EOI" severity failure;
  for stroke in 1 to 4 loop
   send_byte(x"E0");send_byte(x"75");send_byte(x"E0");send_byte(x"F0");send_byte(x"75");
   service(x"3A",EOI_DELAY);service(x"BA",EOI_DELAY);
   send_byte(x"14");send_byte(x"F0");send_byte(x"14");
   service(x"74",EOI_DELAY);service(x"F4",EOI_DELAY);
   send_byte(x"76");send_byte(x"76");send_byte(x"F0");send_byte(x"76");
   service(x"00",EOI_DELAY);service(x"80",EOI_DELAY);service(x"00",EOI_DELAY);service(x"80",EOI_DELAY);
  end loop;
  report "PASS queued keyboard make/break through production PIC across delayed EOI";
  finish;
 end process;
 process begin wait for 100 ms;assert false report "watchdog" severity failure;end process;
end;
