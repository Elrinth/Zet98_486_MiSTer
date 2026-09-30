library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
-- Unclaimed C0000h-D7FFFh floats (UMA_OPEN) so EMM386 can find UMB there, as
-- on a PC-9821. The sound ROM (when enabled), DBIOS D0000h-D1FFFh and the
-- disk BIOS resident RAM D8000h-DFFFFh stay claimed.
entity memorymap_uma_tb is end;
architecture test of memorymap_uma_tb is
 signal addr:std_logic_vector(19 downto 1):=(others=>'0');
 signal snd,oe,tga:std_logic:='0';
 signal open_bus,sdr_cs,dbios_cs,stub:std_logic;
 signal romloaded:std_logic:='0';
 signal stub_word:std_logic_vector(15 downto 0);
begin
 dut:entity work.memorymap generic map(SDAWIDTH=>22) port map(
  CPUADDR=>addr,CPUSEL=>"11",CPUTGA=>tga,CPUSTB=>'1',CPUOE=>oe,DMAEN=>'0',
  DMAADDR=>(others=>'0'),DMARD=>'0',DMAWR=>'0',BNK89SEL=>x"08",BNKABSEL=>x"0a",
  SDR_CS=>sdr_cs,SDR_BANK=>open,SDR_ADDR=>open,GRAM_CS=>open,TRAM_CS=>open,TRAM_ADDR=>open,
  ARAM_CS=>open,ARAM_ADDR=>open,NVRAM_CS=>open,NVRAM_ADDR=>open,CGWIN_CS=>open,
  DBIOS_CS=>dbios_cs,DBIOS_ADDR=>open,UMA_OPEN=>open_bus,
  SOUNDROM=>romloaded,SND_STUB=>stub,SND_STUB_WORD=>stub_word,
  ITFEN=>'0',BIOSEN=>'1',SOUNDEN=>snd,VSEL=>'0',EMSEN=>'0',NECEMSEN=>'0',
  EMSA0=>x"00",EMSA1=>x"00",EMSA2=>x"00",EMSA3=>x"00",MRD=>open,MWR=>open,
  clk=>'0',rstn=>'1');
 process
  variable expect:std_logic;
  variable checked:natural:=0;
 begin
  for s in 0 to 1 loop
   if s=1 then snd<='1'; else snd<='0'; end if;
   for page in 16#80# to 16#ff# loop  -- 80000h..FFFFFh in 4 KiB steps (CPUADDR is a word address)
    for w in 0 to 1 loop
     for tg in 0 to 1 loop
      addr<=std_logic_vector(to_unsigned(page*2048+w*2047,19));
      if tg=1 then tga<='1'; else tga<='0'; end if;
      oe<=std_logic(to_unsigned(w,1)(0));
      wait for 1 ns;
      expect:='0';
      if tg=0 and page>=16#c0# and page<16#d8# then
       expect:='1';
       if page>=16#cc# and page<16#d0# and s=1 then expect:='0'; end if;  -- sound ROM
       if page>=16#d0# and page<16#d2# then expect:='0'; end if;          -- DBIOS
      end if;
      assert open_bus=expect report "UMA_OPEN mismatch page="&integer'image(page)&" sound="&integer'image(s)&" tga="&integer'image(tg) severity failure;
      -- The SDRAM cycle still runs, so the access is acknowledged.
      if expect='1' then assert sdr_cs='1' report "open UMA lost its SDRAM cycle" severity failure; end if;
      checked:=checked+1;
     end loop;
    end loop;
   end loop;
  end loop;
  report "PASS UMA open-bus map: "&integer'image(checked)&" cases";
  -- Sound BIOS stub: NP2kai header bytes 01 00 00 00 D2 00 08 00 CB at
  -- CC2E00h, FFh elsewhere in CC000h-CFFFFh; a loaded ROM replaces it.
  tga<='0'; snd<='1';
  for w in 0 to 8191 loop
   addr<=std_logic_vector(to_unsigned(16#cc000#/2+w,19));
   wait for 1 ns;
   assert stub='1' and open_bus='0' report "sound window not stubbed" severity failure;
   case w is
    when 16#1700# => assert stub_word=x"0001" report "stub CC2E00h" severity failure;
    when 16#1702# => assert stub_word=x"00d2" report "stub CC2E04h" severity failure;
    when 16#1703# => assert stub_word=x"0008" report "stub CC2E06h" severity failure;
    when 16#1701# => assert stub_word=x"0000" report "stub CC2E02h" severity failure;
    when 16#1704# => assert stub_word=x"ffcb" report "stub CC2E08h" severity failure;
    when others => assert stub_word=x"ffff" report "stub not FFh at word "&integer'image(w) severity failure;
   end case;
  end loop;
  romloaded<='1'; wait for 1 ns;
  assert stub='0' report "loaded sound ROM still stubbed" severity failure;
  romloaded<='0'; snd<='0'; wait for 1 ns;
  assert stub='0' and open_bus='1' report "hidden sound window not open" severity failure;
  report "PASS sound BIOS stub: 8192 words";
  stop; wait;
 end process;
end;
