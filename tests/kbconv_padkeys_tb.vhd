-- Gamepad keys through the production converter (padkeys port). Uses the
-- adapter and table models from kbconv_backpressure_tb.vhd.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity kbconv_padkeys_tb is end;
architecture test of kbconv_padkeys_tb is
 signal clk:std_logic:='0';signal rstn:std_logic:='0';
 signal cs,addr,rd,wr:std_logic:='0';signal data:std_logic_vector(7 downto 0);
 signal oe,irq,kco,kdo,emurx:std_logic;
 signal kci,kdi:std_logic:='1';signal unused1,unused2:std_logic_vector(7 downto 0);
 signal pad:std_logic_vector(15 downto 0):=(others=>'0');
begin
 clk<=not clk after 25 ns;
 dut:entity work.KBCONV generic map(CLKCYC=>20000,SFTCYC=>400,RPSET=>0)
 port map(CS=>cs,ADDR=>addr,RD=>rd,WR=>wr,RDAT=>data,WDAT=>x"00",OE=>oe,INT=>irq,
 KBCLKIN=>kci,KBCLKOUT=>kco,KBDATIN=>kdi,KBDATOUT=>kdo,emuen=>'0',emurx=>emurx,
 emurxdat=>unused1,padkeys=>pad,monout=>unused2,clk=>clk,rstn=>rstn);
 process
  type codes is array(1 to 3) of std_logic_vector(7 downto 0);
  procedure cycles(n:natural) is begin for i in 1 to n loop wait until rising_edge(clk);end loop;wait for 1 ns;end;
  procedure send_byte(b:std_logic_vector(7 downto 0)) is
  begin
   for i in 0 to 7 loop kdi<=b(i);kci<='1';cycles(3);kci<='0';cycles(3);end loop;
   kci<='1';cycles(3200);
  end;
  procedure read_byte(got:out std_logic_vector(7 downto 0)) is
  begin
   for i in 1 to 200 loop exit when irq='1';cycles(1);end loop;
   assert irq='1' report "pending key event missing" severity failure;
   cs<='1';addr<='0';rd<='1';cycles(3);got:=data;
   report "read " & to_hstring(data);
   rd<='0';cs<='0';cycles(1);
   assert irq='0' report "IRQ did not clear after data read" severity failure;
   cycles(8);
  end;
  procedure read_key(expected:std_logic_vector(7 downto 0)) is
   variable got:std_logic_vector(7 downto 0);
  begin
   read_byte(got);
   assert got=expected report "wrong key event: " & to_hstring(got) & " expected " & to_hstring(expected) severity failure;
  end;
  -- Keys that change together arrive in scan order: compare as a set.
  procedure read_set(want:codes; n:natural) is
   variable got:std_logic_vector(7 downto 0);
   variable seen:std_logic_vector(1 to 3):="000";
   variable hit:boolean;
  begin
   for k in 1 to n loop
    read_byte(got);hit:=false;
    for j in 1 to n loop
     if not hit and seen(j)='0' and want(j)=got then seen(j):='1';hit:=true;end if;
    end loop;
    assert hit report "unexpected key event " & to_hstring(got) severity failure;
   end loop;
  end;
  procedure quiet is
  begin
   cycles(400);
   assert irq='0' report "unexpected extra key event " & to_hstring(data) severity failure;
  end;
 begin
  cycles(5);rstn<='1';cycles(30000);
  -- Keypad 4 press and release.
  pad(2)<='1';read_key(x"46");quiet;
  pad(2)<='0';read_key(x"C6");quiet;
  -- Two keys at once, then a third before the guest read the first.
  pad(8)<='1';pad(11)<='1';cycles(2);pad(9)<='1';
  read_set((x"29",x"2A",x"70"),3);quiet;
  pad(8)<='0';pad(9)<='0';pad(11)<='0';
  read_set((x"A9",x"AA",x"F0"),3);quiet;
  -- A pad key never splits an extended keyboard sequence (E0 75 = up).
  send_byte(x"E0");pad(0)<='1';cycles(200);
  assert irq='0' report "pad key reported inside an open E0 sequence" severity failure;
  send_byte(x"75");
  read_key(x"3A");read_key(x"43");quiet;
  send_byte(x"E0");send_byte(x"F0");pad(0)<='0';cycles(200);
  assert irq='0' report "pad key reported inside an open E0 F0 sequence" severity failure;
  send_byte(x"75");
  read_key(x"BA");read_key(x"C3");quiet;
  -- Keyboard and pad on the same key: legacy typematic break/make.
  send_byte(x"76");read_key(x"00");
  pad(13)<='1';read_key(x"80");read_key(x"00");quiet;
  pad(13)<='0';read_key(x"80");
  send_byte(x"F0");send_byte(x"76");read_key(x"80");quiet;
  -- Switching the option off releases held keys.
  pad(3)<='1';pad(15)<='1';read_set((x"48",x"62",x"00"),2);
  pad<=(others=>'0');read_set((x"C8",x"E2",x"00"),2);quiet;
  -- Reset forgets reported keys: nothing is replayed afterwards.
  pad(12)<='1';read_key(x"1C");
  pad(12)<='0';rstn<='0';cycles(5);rstn<='1';cycles(30000);
  assert irq='0' report "stale pad event after reset" severity failure;
  report "PASS gamepad keys";stop;wait;
 end process;
 process begin wait for 40 ms;assert false report "pad key test timeout" severity failure;end process;
end;
