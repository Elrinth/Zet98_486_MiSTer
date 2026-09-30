LIBRARY	IEEE,work;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;
	USE work.mem_addr_pkg.all;

entity memorymap is
generic(
	SDAWIDTH		:integer	:=23
);
port(
	CPUADDR		:in std_logic_vector(19 downto 1);
	CPUSEL		:in std_logic_vector(1 downto 0);
	CPUTGA		:in std_logic;
	CPUSTB		:in std_logic;
	CPUOE		:in std_logic;
	DMAEN		:in std_logic;
	DMAADDR		:in std_logic_vector(19 downto 1);
	DMARD		:in std_logic;
	DMAWR		:in std_logic;
	
	BNK89SEL	:in std_logic_vector(7 downto 0);
	BNKABSEL	:in std_logic_vector(7 downto 0);
	
	SDR_CS		:out std_logic;
	SDR_BANK	:out std_logic_vector(1 downto 0);
	SDR_ADDR	:out std_logic_vector(SDAWIDTH-1 downto 0);
	
	GRAM_CS		:out std_logic;
	
	TRAM_CS		:out std_logic;
	TRAM_ADDR	:out std_logic_vector(11 downto 0);
	
	ARAM_CS		:out std_logic;
	ARAM_ADDR	:out std_logic_vector(11 downto 0);
	
	NVRAM_CS	:out std_logic;
	NVRAM_ADDR	:out std_logic_vector(2 downto 0);
	-- CG window A4000h-A4FFFh (font pattern of the code set at A1h/A3h)
	CGWIN_CS	:out std_logic;
	
	DBIOS_CS	:out std_logic;
	DBIOS_ADDR	:out std_logic_vector(12 downto 1);
	-- No device in C0000h-D7FFFh: reads float to FFh as on a PC-98, so
	-- EMM386 can turn the block into UMB. The SDRAM cycle still runs (and
	-- acknowledges) into unused shadow RAM.
	UMA_OPEN	:out std_logic;
	-- Sound BIOS window with no ROM image loaded: reads FFh except NP2kai's
	-- default header (01 00 00 00 D2 00 08 00 CB at CC2E00h), which
	-- programs such as Hello Gre's MUSIC.EXE look for.
	SOUNDROM	:in std_logic := '0';
	SND_STUB	:out std_logic;
	SND_STUB_WORD	:out std_logic_vector(15 downto 0);
	-- CPU (not DMA) access to fixed main RAM below A0000h, for the read
	-- line buffer (mainram_linebuf).
	MAIN_RAM	:out std_logic;

	ITFEN		:in std_logic;
	BIOSEN		:in std_logic;
	SOUNDEN		:in std_logic;
	VSEL		:in std_logic;
	
	EMSEN		:in std_logic;
	NECEMSEN	:in std_logic;
	EMSA0		:in std_logic_vector(7 downto 0);
	EMSA1		:in std_logic_vector(7 downto 0);
	EMSA2		:in std_logic_vector(7 downto 0);
	EMSA3		:in std_logic_vector(7 downto 0);
	
	MRD			:out std_logic;
	MWR			:out std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);
end memorymap;

architecture rtl of memorymap is
type sel_t is(
	sel_MRAM,
	sel_VRAM0,
	sel_VRAM1,
	sel_VRAM2,
	sel_VRAM3,
	sel_TRAM,
	sel_ARAM,
	sel_NVRAM,
	sel_CGWIN,
	sel_BIOS,
	sel_ITF,
	sel_SOUND,
	sel_SASI,
	sel_UMA,
	sel_EMS0,
	sel_EMS1,
	sel_EMS2,
	sel_EMS3,
	sel_NECEMS0,
	sel_NECEMS1,
	sel_NECEMS2,
	sel_NECEMS3
);
signal	MSEL,W8SEL,WASEL	:sel_t;
signal	SDWADDR	:std_logic_vector(27 downto 0);
constant allzero	:std_logic_vector(27 downto 0)	:=(others=>'0');
signal	CPUSEG	:std_logic_vector(15 downto 0);
signal	SELADDR	:std_logic_Vector(19 downto 1);
signal	MODADDR	:std_logic_Vector(19 downto 1);
signal	UMASEL	:std_logic;
signal	UMAADDR	:std_logic_vector(7 downto 1);
begin
	SELADDR<=CPUADDR when DMAEN='0' else DMAADDR;
	MODADDR<=	BNK89SEL(3 downto 1) & SELADDR(16 downto 1) when SELADDR(19 downto 17)="100" else
				BNKABSEL(3 downto 1) & SELADDR(16 downto 1) when SELADDR(19 downto 17)="101" else
				SELADDR(19 downto 1);
	CPUSEG<=MODADDR(19 downto 4);
	UMASEL<='1' when SELADDR(19 downto 17)="100" and BNK89SEL(7 downto 4)/=x"0" else
			'1' when SELADDR(19 downto 17)="101" and BNKABSEL(7 downto 4)/=x"0" else
			'0';
	UMAADDR<=	BNK89SEL(7 downto 1) when SELADDR(19 downto 17)="100" else
				BNKABSEL(7 downto 1) when SELADDR(19 downto 17)="101" else
				(others=>'0');

	MSEL<=
		sel_UMA		when UMASEL='1' else
		sel_ITF		when CPUSEG>=ADDR_ITF and ITFEN='1' else
		sel_BIOS	when CPUSEG>=ADDR_BIOS and BIOSEN='1' else
		sel_SOUND	when CPUSEG>=ADDR_SOUND and CPUSEG<(ADDR_SOUND+WIDTH_SOUND) else
		sel_SASI	when CPUSEG>=ADDR_SASI and CPUSEG<(ADDR_SASI+WIDTH_SASI) else
		sel_NECEMS0	when CPUSEG>=ADDR_NECEMS0 and CPUSEG<(ADDR_NECEMS0+WIDTH_NECEMS0) and NECEMSEN='1' else
		sel_NECEMS1	when CPUSEG>=ADDR_NECEMS1 and CPUSEG<(ADDR_NECEMS1+WIDTH_NECEMS1) and NECEMSEN='1'  else
		sel_NECEMS2	when CPUSEG>=ADDR_NECEMS2 and CPUSEG<(ADDR_NECEMS2+WIDTH_NECEMS2) and NECEMSEN='1'  else
		sel_NECEMS3	when CPUSEG>=ADDR_NECEMS3 and CPUSEG<(ADDR_NECEMS3+WIDTH_NECEMS3) and NECEMSEN='1'  else
		sel_VRAM0	when CPUSEG>=ADDR_VRAM0 and CPUSEG<(ADDR_VRAM0+WIDTH_VRAM0) else
		sel_VRAM1	when CPUSEG>=ADDR_VRAM1 and CPUSEG<(ADDR_VRAM1+WIDTH_VRAM1) else
		sel_VRAM2	when CPUSEG>=ADDR_VRAM2 and CPUSEG<(ADDR_VRAM2+WIDTH_VRAM2) else
		sel_VRAM3	when CPUSEG>=ADDR_VRAM3 and CPUSEG<(ADDR_VRAM3+WIDTH_VRAM3) else
		sel_NVRAM	when CPUSEG>=ADDR_NVRAM and CPUSEG<(ADDR_NVRAM+WIDTH_NVRAM) else
		-- CG window: font pattern of the character selected at A1h/A3h/A5h
		-- (Black Thorne and others copy text glyphs from A400:0000).
		sel_CGWIN	when CPUSEG>=x"a400" and CPUSEG<x"a500" else
		sel_TRAM	when CPUSEG>=ADDR_TRAM and CPUSEG<(ADDR_TRAM+WIDTH_TRAM) else
		sel_ARAM	when CPUSEG>=ADDR_ARAM and CPUSEG<(ADDR_ARAM+WIDTH_ARAM) else
		sel_EMS0	when CPUSEG>=ADDR_EMS0 and CPUSEG<(ADDR_EMS0+WIDTH_EMS0) and EMSEN='1' else
		sel_EMS1	when CPUSEG>=ADDR_EMS1 and CPUSEG<(ADDR_EMS1+WIDTH_EMS1) and EMSEN='1'  else
		sel_EMS2	when CPUSEG>=ADDR_EMS2 and CPUSEG<(ADDR_EMS2+WIDTH_EMS2) and EMSEN='1'  else
		sel_EMS3	when CPUSEG>=ADDR_EMS3 and CPUSEG<(ADDR_EMS3+WIDTH_EMS3) and EMSEN='1'  else
		sel_MRAM;
	
		
	SDWADDR<=	RAM_ITF+(allzero(27 downto 19) & (MODADDR-(ADDR_ITF & "000")))		when MSEL=sel_ITF else --or (MSEL=sel_RWIN8 and W8SEL=sel_ITF) or (MSEL=sel_RWINA and WASEL=sel_ITF)) else
				RAM_BIOS+(allzero(27 downto 19) & (MODADDR-(ADDR_BIOS & "000")))		when MSEL=sel_BIOS else --or (MSEL=sel_RWIN8 and W8SEL=sel_BIOS) or (MSEL=sel_RWINA and WASEL=sel_BIOS)) else
				RAM_SOUND+(allzero(27 downto 19) & (MODADDR-(ADDR_SOUND & "000")))	when MSEL=sel_SOUND and SOUNDEN='1' else
				RAM_SASI+(allzero(27 downto 19) & (MODADDR-(ADDR_SASI & "000")))		when MSEL=sel_SASI else
				RAM_VRAMF+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM0 & "000")) & "00")				when MSEL=sel_VRAM0 and VSEL='0' else
				RAM_VRAMB+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM0 & "000")) & "00")				when MSEL=sel_VRAM0 and VSEL='1' else
				RAM_VRAMF+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM1 & "000")) & "01")				when MSEL=sel_VRAM1 and VSEL='0' else
				RAM_VRAMB+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM1 & "000")) & "01")				when MSEL=sel_VRAM1 and VSEL='1' else
				RAM_VRAMF+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM2 & "000")) & "10")				when MSEL=sel_VRAM2 and VSEL='0' else
				RAM_VRAMB+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM2 & "000")) & "10")				when MSEL=sel_VRAM2 and VSEL='1' else
				RAM_VRAMF+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM3 & "000")) & "11")				when MSEL=sel_VRAM3 and VSEL='0' else
				RAM_VRAMB+(allzero(27 downto 21) & (MODADDR-(ADDR_VRAM3 & "000")) & "11")				when MSEL=sel_VRAM3 and VSEL='1' else
				RAM_EMS+(allzero(27 downto 21) & EMSA0 & '0' & x"000")+(allzero(21 downto 19) & MODADDR-(ADDR_EMS0 & "000")) when (MSEL=sel_EMS0 or MSEL=sel_NECEMS0) else
				RAM_EMS+(allzero(27 downto 21) & EMSA1 & '0' & x"000")+(allzero(21 downto 19) & MODADDR-(ADDR_EMS1 & "000")) when (MSEL=sel_EMS1 or MSEL=sel_NECEMS1) else
				RAM_EMS+(allzero(27 downto 21) & EMSA2 & '0' & x"000")+(allzero(21 downto 19) & MODADDR-(ADDR_EMS2 & "000")) when (MSEL=sel_EMS2 or MSEL=sel_NECEMS2) else
				RAM_EMS+(allzero(27 downto 21) & EMSA3 & '0' & x"000")+(allzero(21 downto 19) & MODADDR-(ADDR_EMS3 & "000")) when (MSEL=sel_EMS3 or MSEL=sel_NECEMS3) else
				RAM_EMS+(allzero(27 downto 21) & UMAADDR(5 downto 1) & MODADDR(16 downto 1))				when MSEL=sel_UMA else
				RAM_MAIN+(allzero(27 downto 19) & MODADDR);
	
	TRAM_ADDR<=	MODADDR(12 downto 1);
	ARAM_ADDR<=	MODADDR(12 downto 1);
	NVRAM_ADDR<=MODADDR(4 downto 2);
	DBIOS_ADDR<=MODADDR(12 downto 1);
	
	SDR_CS<=	'0' when CPUTGA='1' and DMAEN='0' else
				'0' when MSEL=sel_TRAM else
				'0' when MSEL=sel_ARAM else
				'0' when MSEL=sel_NVRAM else
				'0' when MSEL=sel_CGWIN else
				'1';
	
	GRAM_CS<=	'0' when CPUTGA='1'  and DMAEN='0'else
				'1' when MSEL=sel_VRAM0 else
				'1' when MSEL=sel_VRAM1 else
				'1' when MSEL=sel_VRAM2 else
				'1' when MSEL=sel_VRAM3 else
				'0';
	
	TRAM_CS<=	'0' when CPUTGA='1'  and DMAEN='0'else
				'1' when MSEL=sel_TRAM else
				'0';
	
	ARAM_CS<=	'0' when CPUTGA='1'  and DMAEN='0'else
				'1' when MSEL=sel_ARAM else
				'0';
	
	NVRAM_CS<=	'0' when CPUTGA='1'  and DMAEN='0'else
				'1' when MSEL=sel_NVRAM else
				'0';

	CGWIN_CS<=	'0' when CPUTGA='1' or DMAEN='1' else
				'1' when MSEL=sel_CGWIN else
				'0';
				
	DBIOS_CS<=	'0' when CPUTGA='1' and DMAEN='0' else
				'1' when MSEL=sel_SASI else
				'0';

	-- D8000h-DFFFFh stays RAM: the disk BIOS resident lives there.
	UMA_OPEN<=	'0' when CPUTGA='1' and DMAEN='0' else
				'0' when CPUSEG<x"c000" or CPUSEG>=x"d800" else
				'1' when MSEL=sel_MRAM else
				'1' when MSEL=sel_SOUND and SOUNDEN='0' else
				'0';

	MAIN_RAM<=	'0' when CPUTGA='1' or DMAEN='1' else
				'1' when MSEL=sel_MRAM and CPUSEG<x"a000" else
				'0';

	SND_STUB<=	'0' when CPUTGA='1' and DMAEN='0' else
				'1' when MSEL=sel_SOUND and SOUNDEN='1' and SOUNDROM='0' else
				'0';
	with MODADDR(13 downto 1) select SND_STUB_WORD<=
		x"0001" when '1' & x"700",		-- CC2E00h: 01 00
		x"0000" when '1' & x"701",		-- CC2E02h: 00 00
		x"00d2" when '1' & x"702",		-- CC2E04h: D2 00
		x"0008" when '1' & x"703",		-- CC2E06h: 08 00
		x"ffcb" when '1' & x"704",		-- CC2E08h: CB (RETF), then FFh
		x"ffff" when others;			-- as NP2kai: the rest reads empty
		-- (Zeros here made Flame Zapper's NAX driver stall its intro.)
	
	MRD<=	DMARD when DMAEN='1' else
			'0' when CPUTGA='1' else
			'1' when CPUOE='0' and CPUSTB='1' else
			'0';

	MWR<=	DMAWR	when DMAEN='1' else
			'0' when CPUTGA='1' else
			'1' when CPUOE='1' and CPUSTB='1' else
			'0';
	
	SDR_BANK<=SDWADDR(SDAWIDTH+1 downto SDAWIDTH);
	SDR_ADDR<=SDWADDR(SDAWIDTH-1 downto 0);
	
end rtl;

