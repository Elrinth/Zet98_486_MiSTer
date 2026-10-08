library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
-- Exercise the bank selector together with the production memory mapper.
entity rombank_tb is end;
architecture test of rombank_tb is
 signal addr:std_logic_vector(19 downto 1):=(others=>'0');
 signal snd,oe,tga:std_logic:='0';
 signal clk:std_logic:='0';
 signal rstn,rd,wr,bank,bank_cs,bank_oe:std_logic:='0';
 signal ea:std_logic_vector(15 downto 0):=x"FFFF";
 signal wd,q:std_logic_vector(7 downto 0);
 signal word:std_logic_vector(15 downto 0);
 signal b89,bab:std_logic_vector(7 downto 0):=x"00";
 signal open_bus,sdr_cs,dbios_cs,stub:std_logic;
 signal romloaded:std_logic:='0';
 signal stub_word:std_logic_vector(15 downto 0);
begin
 clk<=not clk after 5 ns;
 bankreg:entity work.pc98_rombank port map(clk,rstn,ea,rd,wr,wd,q,bank_oe,bank);
 dut:entity work.memorymap generic map(SDAWIDTH=>22) port map(
  CPUADDR=>addr,CPUSEL=>"11",CPUTGA=>tga,CPUSTB=>'1',CPUOE=>oe,DMAEN=>'0',
  DMAADDR=>(others=>'0'),DMARD=>'0',DMAWR=>'0',BNK89SEL=>b89,BNKABSEL=>bab,
  SDR_CS=>sdr_cs,SDR_BANK=>open,SDR_ADDR=>open,GRAM_CS=>open,TRAM_CS=>open,TRAM_ADDR=>open,
  ARAM_CS=>open,ARAM_ADDR=>open,NVRAM_CS=>open,NVRAM_ADDR=>open,CGWIN_CS=>open,
  PCI_BANK=>bank,PCI_CS=>bank_cs,PCI_WORD=>word,DBIOS_CS=>dbios_cs,DBIOS_ADDR=>open,UMA_OPEN=>open_bus,
  SOUNDROM=>romloaded,SND_STUB=>stub,SND_STUB_WORD=>stub_word,
  ITFEN=>'0',BIOSEN=>'1',SOUNDEN=>snd,VSEL=>'0',EMSEN=>'0',NECEMSEN=>'0',
  EMSA0=>x"00",EMSA1=>x"00",EMSA2=>x"00",EMSA3=>x"00",MRD=>open,MWR=>open,
  clk=>'0',rstn=>'1');
 process
  procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
  procedure select_bank(n:natural) is begin
   ea<=x"063C"; wd<=std_logic_vector(to_unsigned(n,8)); wr<='1'; tick; wr<='0'; rd<='1'; tick;
   assert bank_oe='1' and q=std_logic_vector(to_unsigned(n,8)) report "selector readback" severity failure;
   rd<='0'; tick; assert bank_oe='0' severity failure;
  end;
  procedure address(n:natural) is begin addr<=std_logic_vector(to_unsigned(n/2,19)); wait for 1 ns; end;
 begin
  tick; rstn<='1'; tick;
  assert q=x"FE" and bank='0' report "reset bank" severity failure;
  -- Exercise all selector values, including upper bits preserved by NEC BIOS.
  for n in 0 to 255 loop
   select_bank(n);
   for p in 0 to 255 loop
    address(p*4096);
    if n mod 4=1 and p>=16#D8# and p<=16#DF# then
     assert bank_cs='1' report "missing overlay" severity failure;
    else assert bank_cs='0' report "overlay outside bank/window" severity failure; end if;
   end loop;
  end loop;
  select_bank(1);
  for w in 0 to 16383 loop
   address(16#D8000#+2*w);
   assert bank_cs='1' and sdr_cs='1' report "read acknowledgement lost" severity failure;
   if w=6 then assert word=x"FFCB" report "POST RETF entry" severity failure;
   else assert word=x"FFFF" report "unexpected executable firmware" severity failure; end if;
  end loop;
  address(16#D800C#); tga<='1'; wait for 1 ns;
  assert bank_cs='0' report "I/O shadowed by firmware" severity failure;
  tga<='0'; b89<=x"0C"; bab<=x"0C";
  address(16#9800C#); assert bank_cs='1' and word=x"FFCB" report "89 alias" severity failure;
  address(16#B800C#); assert bank_cs='1' and word=x"FFCB" report "AB alias" severity failure;
  select_bank(2); assert bank_cs='0' report "resident not restored" severity failure;
  ea<=x"063D"; wd<=x"01"; wr<='1'; tick; wr<='0';
  assert bank='0' report "odd partner wrote selector" severity failure;
  select_bank(1); rstn<='0'; tick; assert bank='0' and q=x"FE" severity failure;
  report "PASS: all 256 bank selectors, address isolation, 32KiB ROM, aliases and reset";
  stop; wait;
 end process;
end;
