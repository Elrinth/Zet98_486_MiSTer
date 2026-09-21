LIBRARY	IEEE,work;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;
	USE work.mem_addr_pkg.all;
	use work.FDC_sectinfo.all;
	use work.FDC_timing.all;

entity Zet98MiSTer is
generic(
	SYSFREQ		:integer	:=20000;		--CPU clock(kHz)
	SND			:integer	:=2;			--0:none 1:OPN(-26) 2:OPNA(-73) 3:experimental -86 PCM
	CPU486      :integer :=0;          -- opt-in ao486 bring-up build
	EXT_RAM_MB  :integer :=0;          -- experimental DDR-backed extended memory
	LOWMEM_CACHE:integer :=0;          -- experimental conventional-RAM read cache
	LOWMEM_CACHE_KB:integer :=8
);
port(
	ramclk	:in std_logic;
	cpuclk	:in std_logic;
	vidclk	:in std_logic;
	plllock	:in std_logic;
	
	sysrtc	:in std_logic_vector(64 downto 0);
	
    -- SD-RAM ports
	pMemClk     : out std_logic;                        -- SD-RAM Clock
	pMemCke     : out std_logic;                        -- SD-RAM Clock enable
	pMemCs_n    : out std_logic;                        -- SD-RAM Chip select
	pMemRas_n   : out std_logic;                        -- SD-RAM Row/RAS
	pMemCas_n   : out std_logic;                        -- SD-RAM /CAS
	pMemWe_n    : out std_logic;                        -- SD-RAM /WE
	pMemUdq     : out std_logic;                        -- SD-RAM UDQM
	pMemLdq     : out std_logic;                        -- SD-RAM LDQM
	pMemBa1     : out std_logic;                        -- SD-RAM Bank select address 1
	pMemBa0     : out std_logic;                        -- SD-RAM Bank select address 0
	pMemAdr     : out std_logic_vector(12 downto 0);    -- SD-RAM Address
	pMemDat     : inout std_logic_vector(15 downto 0);  -- SD-RAM Data
	pDdrAddress : out std_logic_vector(28 downto 0);
	pDdrWriteData : out std_logic_vector(63 downto 0);
	pDdrByteEnable, pDdrBurstCount : out std_logic_vector(7 downto 0);
	pDdrRead, pDdrWrite : out std_logic;
	pDdrBusy, pDdrReadValid : in std_logic;
	pDdrReadData : in std_logic_vector(63 downto 0);

	-- ROM image loader
	LDR_ADDR		:in std_logic_vector(19 downto 0);
	LDR_OE		:in std_logic;
	LDR_WDAT		:in std_logic_vector(7 downto 0);
	LDR_WR		:in std_logic;
	LDR_ACK		:out std_logic;
	LDR_DONE		:in std_logic;

	-- PS/2 keyboard ports
	pPs2Clkin	: in std_logic;
	pPs2Clkout	: out std_logic;
	pPs2Datin	: in std_logic;
	pPs2Datout	: out std_logic;
	pPmsClkin	: in std_logic;
	pPmsClkout	: out std_logic;
	pPmsDatin	: in std_logic;
	pPmsDatout	: out std_logic;
	
	-- Joystick ports (Port_A, Port_B)
	pJoyA       : inout std_logic_vector( 5 downto 0);
	pJoyB       : inout std_logic_vector( 5 downto 0);

--MiSTer diskimage
	pFDSYNC		:in std_logic_Vector(1 downto 0);
	pFDEJECT		:in std_logic_vector(1 downto 0);
	mist_mounted	:in std_logic_vector(3 downto 0);	--SRAM & HDD & FDD1 &FDD0
	mist_readonly	:in std_logic_vector(3 downto 0);
	mist_imgsize	:in std_logic_vector(63 downto 0);

	mist_lba			:out std_logic_vector(31 downto 0);
	mist_rd			:out std_logic_vector(3 downto 0);
	mist_wr			:out std_logic_vector(3 downto 0);
	mist_ack			:in std_logic;

	mist_buffaddr	:in std_logic_vector(8 downto 0);
	mist_buffdout	:in std_logic_vector(7 downto 0);
	mist_buffdin	:out std_logic_vector(7 downto 0);
	mist_buffwr		:in std_logic;

	psramld			:in std_logic;
	psramst			:in std_logic;
	-- Optional PC-98 ATA task file in the MiSTer wrapper (same CPU clock).
	pIDEAddress, pIDEWriteData :out std_logic_vector(15 downto 0);
	pIDESelect :out std_logic_vector(1 downto 0);
	pIDERead, pIDEWrite, pIDEResetn :out std_logic;
	pIDEReadData :in std_logic_vector(15 downto 0);
	pIDEOE, pIDEIRQ :in std_logic;
	pMPUReadData :in std_logic_vector(7 downto 0);
	pMPUOE, pMPUIRQ :in std_logic;

-- DIP switch, Lamp ports
	pDip1			: in std_logic_vector(1 downto 0);
	pDip2			: in std_logic_vector(7 downto 0);
	pLed			: out std_logic;
	pFloppyAccess : out std_logic_vector(1 downto 0);

	-- Video, Audio/CMT ports
	pVideoR     : out	std_logic_vector( 7 downto 0);  -- RGB_Red / Svideo_C
	pVideoG     : out	std_logic_vector( 7 downto 0);  -- RGB_Grn / Svideo_Y
	pVideoB     : out	std_logic_vector( 7 downto 0);  -- RGB_Blu / CompositeVideo

	pVideoHS		: out std_logic;                        -- Csync(RGB15K), HSync(VGA31K)
	pVideoVS		: out std_logic;                        -- Audio(RGB15K), VSync(VGA31K)
	pVideoEN		: out std_logic;
	pVideoClk	: out std_logic;

	pSndL			: out		std_logic_vector(15 downto 0);  -- Sound-L
	pSndR			: out		std_logic_vector(15 downto 0);  -- Sound-R
	pStartupBeeps : in std_logic := '0'; -- Bypass the default startup-only speaker mute.

	rstn		:in std_logic
);
end Zet98MiSTer;

architecture rtl of Zet98MiSTer is

component cyclone_asmiblock   	-- Altera specific component
    port (
      dclkin   : in std_logic;  	-- DCLK
      scein    : in std_logic;  	-- nCSO
      sdoin    : in std_logic;  	-- ASDO
      oe       : in std_logic;  	--(1=disable(Hi-Z))
      data0out : out std_logic  	-- DATA0
    );
end component;

component SPI_IF
	port(
		WRDAT	:in std_logic_vector(7 downto 0);
		RDDAT	:out std_logic_vector(7 downto 0);
		WR		:in std_logic;
		RD		:in std_logic;
		BUSY	:out std_logic;

		SCLK	:out std_logic;
		SDI		:in std_logic;
		SDO		:out std_logic;
		
		SFT		:in std_logic;
		clk		:in std_logic;
		rstn	:in std_logic
	);
end component;

component pcm86
generic(CLOCK_HZ :integer :=20000000);
port(
    clk, reset :in std_logic;
    address :in std_logic_vector(15 downto 0);
    read, write :in std_logic;
    writedata :in std_logic_vector(7 downto 0);
    readdata :out std_logic_vector(7 downto 0);
    selected, irq, opna_extended, opna_muted :out std_logic;
    audio_l, audio_r :out std_logic_vector(15 downto 0);
    sample_valid :out std_logic
);
end component;

component pc98_ao486
generic(EXT_RAM_MB :integer :=0; LOWMEM_CACHE :integer :=0; LOWMEM_CACHE_KB :integer :=8);
port(
    clk, reset :in std_logic;
    cache_invalidate :in std_logic;
    interrupt_do :in std_logic;
    interrupt_vector :in std_logic_vector(7 downto 0);
    interrupt_done :out std_logic;
    bus_address :out std_logic_vector(19 downto 1);
    bus_select :out std_logic_vector(1 downto 0);
    bus_writedata :out std_logic_vector(15 downto 0);
    bus_write, bus_strobe, bus_io :out std_logic;
    bus_readdata :in std_logic_vector(15 downto 0);
    bus_ack :in std_logic;
    unmapped_access :out std_logic;
    ddr_address :out std_logic_vector(28 downto 0);
    ddr_writedata :out std_logic_vector(63 downto 0);
    ddr_byteenable, ddr_burstcount :out std_logic_vector(7 downto 0);
    ddr_read, ddr_write :out std_logic;
    ddr_busy, ddr_readdatavalid :in std_logic;
    ddr_readdata :in std_logic_vector(63 downto 0)
);
end component;

component zet
port(
	wb_clk_i	:in std_logic;
	wb_rst_i	:in std_logic;
	wb_dat_i	:in std_logic_vector(15 downto 0);
	wb_dat_o	:out std_logic_vector(15 downto 0);
	wb_adr_o	:out std_logic_vector(19 downto 1);
	wb_we_o		:out std_logic;
	wb_tga_o	:out std_logic;
	wb_sel_o	:out std_logic_vector(1 downto 0);
	wb_stb_o	:out std_logic;
	wb_cyc_o	:out std_logic;
	wb_ack_i	:in std_logic;
	wb_tgc_i	:in std_logic;
	wb_tgc_o	:out std_logic;
	nmi			:in std_logic;
	nmia		:out std_logic;
	pc			:out std_logic_vector(19 downto 0)
);
end component;

component CRTC98 
port(
	TRAM_ADR	:out std_logic_vector(12 downto 0);
	TRAM_DAT	:in std_logic_vector(15 downto 0);
	TRAM_ATR	:in std_logic_vector(7 downto 0);
	
	KNJSEL		:out std_logic_vector(1 downto 0);
	KNJADR		:out std_logic_vector(16 downto 0);
	KNJDAT		:in std_logic_vector(7 downto 0)	:=x"00";
	
	
	GRAMADR		:out std_logic_vector(13 downto 0);
	GRAMRD		:out std_logic;
	GRAMACK		:in std_logic;
	GRAMDAT0	:in std_logic_vector(15 downto 0);
	GRAMDAT1	:in std_logic_vector(15 downto 0);
	GRAMDAT2	:in std_logic_vector(15 downto 0);
	GRAMDAT3	:in std_logic_vector(15 downto 0);
	
	ETRAM_ADR	:out std_logic_vector(11 downto 0);
	ETRAM_DAT	:in std_logic_vector(7 downto 0);
	ECURL			:in std_logic_vector(4 downto 0);
	ECURC			:in std_logic_vector(6 downto 0);
	ECUREN		:in std_logic;

	ROUT		:out std_logic_vector(3 downto 0);
	GOUT		:out std_logic_vector(3 downto 0);
	BOUT		:out std_logic_vector(3 downto 0);
	
	HSYNC		:out std_logic;
	VSYNC		:out std_logic;
	VIDEOEN	:out std_logic;
	
	TBASEADDR	:in std_logic_vector(12 downto 0);
	HMODE		:in std_logic;		-- 1:80chars 0:40chars
	VLINES		:in std_logic_vector(4 downto 0);		-- 1:25lines 0:20lines
	TPITCH		:in std_logic_vector(7 downto 0);

	GRAPHEN		:in std_logic;
	DOTPLINE	:in std_logic_vector(4 downto 0);
	LOWBL		:in std_logic;
	GCOLOR		:in std_logic;
	MONOSEL		:in std_logic_vector(3 downto 0);
	TXTEN		:in std_logic;

	CURADDR		:in std_logic_vector(12 downto 0);
	CURE		:in std_logic;
	CURUPPER	:in integer range 0 to 19;
	CURLOWER	:in integer range 0 to 19;
	CBLINK		:in std_logic;
	BLINKRATE	:in std_logic_vector(4 downto 0);
	
	GBASEADDR0	:in std_logic_vector(13 downto 0);
	GBASEADDR1	:in std_logic_vector(13 downto 0);
	GLINENUM0	:in std_logic_vector(9 downto 0);
	GLINENUM1	:in std_logic_vector(9 downto 0);
	GPITCH		:in std_logic_vector(7 downto 0);

	EMUMODE		:in std_logic;

	VRTC		:out std_logic;
	HRTC		:out std_logic;

	GPALNO		:out std_logic_vector(3 downto 0);
	GPALR		:in std_logic_vector(3 downto 0);
	GPALG		:in std_logic_vector(3 downto 0);
	GPALB		:in std_logic_vector(3 downto 0);

	gclk		:out std_logic;
	clk			:in std_logic;
	rstn		:in std_logic
);
end component;

component SDRAMC
	generic(
		ADRWIDTH		:integer	:=23;
		CLKMHZ			:integer	:=100;			--MHz
		REFCYC			:integer	:=64000/8192;	--usec
        CPU_WRITE_BUNDLE : boolean := false;
        SUB_WRITE_BUNDLE : boolean := false;
        FLOPPY_REQUEST_BUNDLE : boolean := false
	);
	port(
		-- SDRAM PORTS
		PMEMCKE			: OUT	STD_LOGIC;							-- SD-RAM CLOCK ENABLE
		PMEMCS_N		: OUT	STD_LOGIC;							-- SD-RAM CHIP SELECT
		PMEMRAS_N		: OUT	STD_LOGIC;							-- SD-RAM ROW/RAS
		PMEMCAS_N		: OUT	STD_LOGIC;							-- SD-RAM /CAS
		PMEMWE_N		: OUT	STD_LOGIC;							-- SD-RAM /WE
		PMEMUDQ			: OUT	STD_LOGIC;							-- SD-RAM UDQM
		PMEMLDQ			: OUT	STD_LOGIC;							-- SD-RAM LDQM
		PMEMBA1			: OUT	STD_LOGIC;							-- SD-RAM BANK SELECT ADDRESS 1
		PMEMBA0			: OUT	STD_LOGIC;							-- SD-RAM BANK SELECT ADDRESS 0
		PMEMADR			: OUT	STD_LOGIC_VECTOR( 12 DOWNTO 0 );	-- SD-RAM ADDRESS
		PMEMDAT			: INOUT	STD_LOGIC_VECTOR( 15 DOWNTO 0 );	-- SD-RAM DATA

		CPUBNK			:in std_logic_vector(1 downto 0);
		CPUADR			:in std_logic_vector(ADRWIDTH-1 downto 0);
		CPURDAT0		:out std_logic_vector(15 downto 0);
		CPURDAT1		:out std_logic_vector(15 downto 0);
		CPURDAT2		:out std_logic_vector(15 downto 0);
		CPURDAT3		:out std_logic_vector(15 downto 0);
		CPUWDAT0		:in std_logic_vector(15 downto 0);
		CPUWDAT1		:in std_logic_vector(15 downto 0);
		CPUWDAT2		:in std_logic_vector(15 downto 0);
		CPUWDAT3		:in std_logic_vector(15 downto 0);
        CPUPRESERVE :in std_logic_vector(15 downto 0) := x"0000";
		CPUWR1			:in std_logic;
		CPUWR4			:in std_logic;
		CPURD1			:in std_logic;
		CPURD4			:in std_logic;
		CPURMW1			:in std_logic;
		CPURMW4			:in std_logic;
		CPUBSEL			:in std_logic_vector(1 downto 0);
		CPUPSEL			:in std_logic_vector(3 downto 0);
		CPUACK			:out std_logic;
		CPUCLK			:in std_logic;
		
		SUBBNK			:in std_logic_vector(1 downto 0);
		SUBADR			:in std_logic_vector(ADRWIDTH-1 downto 0);
		SUBRDAT0		:out std_logic_vector(15 downto 0);
		SUBRDAT1		:out std_logic_vector(15 downto 0);
		SUBRDAT2		:out std_logic_vector(15 downto 0);
		SUBRDAT3		:out std_logic_vector(15 downto 0);
		SUBWDAT0		:in std_logic_vector(15 downto 0);
		SUBWDAT1		:in std_logic_vector(15 downto 0);
		SUBWDAT2		:in std_logic_vector(15 downto 0);
		SUBWDAT3		:in std_logic_vector(15 downto 0);
        SUBPRESERVE :in std_logic_vector(15 downto 0) := x"0000";
		SUBWR1			:in std_logic;
		SUBWR4			:in std_logic;
		SUBRD1			:in std_logic;
		SUBRD4			:in std_logic;
		SUBRMW1			:in std_logic;
		SUBRMW4			:in std_logic;
		SUBBSEL			:in std_logic_vector(1 downto 0);
		SUBPSEL			:in std_logic_vector(3 downto 0);
		SUBACK			:out std_logic;
		SUBCLK			:in std_logic;
		
		VIDBNK			:in std_logic_vector(1 downto 0);
		VIDADR			:in std_logic_vector(ADRWIDTH-1 downto 0);
		VIDDAT0			:out std_logic_vector(15 downto 0);
		VIDDAT1			:out std_logic_vector(15 downto 0);
		VIDDAT2			:out std_logic_vector(15 downto 0);
		VIDDAT3			:out std_logic_vector(15 downto 0);
		VIDRD			:in std_logic;
		VIDACK			:out std_logic;
		VIDCLK			:in std_logic;
		
		FDEADR			:in std_logic_vector(ADRWIDTH+1 downto 0)	:=(others=>'0');
		FDERD				:in std_logic								:='0';
		FDEWR				:in std_logic								:='0';
		FDERDAT			:out std_logic_Vector(15 downto 0);
		FDEWDAT			:in std_logic_vector(15 downto 0)	:=(others=>'0');
		FDEWAIT			:out std_logic;
		FDECLK			:in std_logic;
		
		FECADR			:in std_logic_vector(ADRWIDTH+1 downto 0)	:=(others=>'0');
		FECRD				:in std_logic								:='0';
		FECWR				:in std_logic								:='0';
		FECRDAT			:out std_logic_vector(15 downto 0);
		FECWDAT			:in std_logic_vector(15 downto 0)	:=(others=>'0');
		FECWAIT			:out std_logic;
		FECCLK			:in std_logic;

		mem_inidone		:out std_logic;
		
		memclk			:in std_logic;
		rstn			:in std_logic
	);
end component;

component memorymap
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
	
	DBIOS_CS	:out std_logic;
	DBIOS_ADDR	:out std_logic_vector(12 downto 1);
	
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
end component;

component IO043F
port(
	CS		:in std_logic;
	WR		:in std_logic;
	WDAT	:in std_logic_vector(7 downto 0);
	
	NECEMSSEL	:out std_logic;
	BNK89SEL	:out std_logic;
	SASIRAMEN	:out std_logic;
	SCSIRAMEN	:out std_logic;
	CACHEFLASH	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component GDC_MMAP
generic(
	SDAWIDTH	:integer	:=23
);
port(
	GDC_ADDR	:in std_logic_vector(17 downto 0);
	
	GRAMSEL		:in std_logic;
	
	RAMBANK		:out std_logic_vector(1 downto 0);
	RAMADDR		:out std_logic_vector(SDAWIDTH-1 downto 0)
);
end component;
component zetpllcv
	port (
		refclk   : in  std_logic := '0'; --  refclk.clk
		rst      : in  std_logic := '0'; --   reset.reset
		outclk_0 : out std_logic;        -- outclk0.clk
		outclk_1 : out std_logic;        -- outclk1.clk
		outclk_2 : out std_logic;        -- outclk2.clk
		outclk_3 : out std_logic;        -- outclk3.clk
		outclk_4 : out std_logic;        -- outclk3.clk
		locked   : out std_logic         --  locked.export
	);
end component;

component tvram
port(
	cs		:in std_logic;
	caddr	:in std_logic_vector(11 downto 0);
	sel		:in std_logic_vector(1 downto 0);
	rd		:in std_logic;
	wr		:in std_logic;
	wdat	:in std_logic_vector(15 downto 0);
	odat	:out std_logic_vector(15 downto 0);
	oe		:out std_logic_vector(1 downto 0);
	ack		:out std_logic;
	cclk	:in std_logic;
	
	vaddr	:in std_logic_vector(11 downto 0);
	vdat	:out std_logic_vector(15 downto 0);
	vclk	:in std_logic;
	
	rstn	:in std_logic
);
end component;

component grcg
generic(SPLIT_RMW : boolean := false);
port(
	iocs	:in std_logic;
	ioaddr	:in std_logic;
	iowr	:in std_logic;
	iowdat	:in std_logic_vector(7 downto 0);
	
	pmemcs	:in std_logic;
	ppsel	:in std_logic_vector(1 downto 0);
	prd		:in std_logic;
	pwr		:in std_logic;
	prddat	:out std_logic_vector(15 downto 0);
	pwrdat	:in std_logic_vector(15 downto 0);
	poe		:out std_logic;
	
	memrd1	:out std_logic;
	memrd4	:out std_logic;
	memwr1	:out std_logic;
	memwr4	:out std_logic;
	memrmw1	:out std_logic;
	memrmw4	:out std_logic;
	memrdat0:in std_logic_vector(15 downto 0);
	memrdat1:in std_logic_vector(15 downto 0);
	memrdat2:in std_logic_vector(15 downto 0);
	memrdat3:in std_logic_vector(15 downto 0);
	memwdat0:out std_logic_vector(15 downto 0);
	memwdat1:out std_logic_vector(15 downto 0);
	memwdat2:out std_logic_vector(15 downto 0);
	memwdat3:out std_logic_vector(15 downto 0);
	memwmask :out std_logic_vector(15 downto 0);
	memwrpsel	:out std_logic_vector(3 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component KBCONV
generic(
	CLKCYC	:integer	:=20000;
	SFTCYC	:integer	:=400;
	RPSET		:integer	:=0
);
port(
	CS		:in std_logic;
	ADDR	:in std_logic;
	RD		:in std_logic;
	WR		:in std_logic;
	RDAT	:out std_logic_vector(7 downto 0);
	WDAT	:in std_logic_vector(7 downto 0);
	OE		:out std_logic;
	INT		:out std_logic;

	KBCLKIN	:in std_logic;
	KBCLKOUT:out std_logic;
	KBDATIN	:in std_logic;
	KBDATOUT:out std_logic;
	
	emuen		:in std_logic;
	emurx		:out std_logic;
	emurxdat	:out std_logic_vector(7 downto 0);

	monout	:out std_logic_vector(7 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component sftgen
generic(
	maxlen	:integer	:=100
);
port(
	len		:in integer range 0 to maxlen;
	sft		:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component IOack
port(
	tga		:in std_logic;
	stb		:in std_logic;
	addr	:in std_logic_vector(15 downto 1);
	sel		:in std_logic_vector(1 downto 0);
	dir		:in std_logic;
	dmaen		:in std_logic;
	iord	:out std_logic;
	iowr	:out std_logic;
	waitn	:in std_logic;
	ack		:out std_logic;
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component z8259 is
generic(
	monlen :integer :=15;
	RETRACTABLE_IRQS :std_logic_vector(7 downto 0) := x"00"
);
port(
	CS		:in std_logic;
	ADDR	:in std_logic;
	DIN		:in std_logic_vector(7 downto 0);
	DOUT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	RD		:in std_logic;
	WR		:in std_logic;
	
	IR0		:in std_logic;
	IR1		:in std_logic;
	IR2		:in std_logic;
	IR3		:in std_logic;
	IR4		:in std_logic;
	IR5		:in std_logic;
	IR6		:in std_logic;
	IR7		:in std_logic;
	
	INT		:out std_logic;
	INTA	:in std_logic;
	
	CASI	:in std_logic_vector(2 downto 0);
	CASO	:out std_logic_vector(2 downto 0);
	CASM	:in std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component FDtiming
generic(
	sysclk	:integer	:=21477		--in kHz
);
port(
	drv0sel		:in std_logic;		--0:300rpm 1:360rpm
	drv1sel		:in std_logic;
	drv0sele	:in std_logic;		--1:speed selectable
	drv1sele	:in std_logic;

	drv0hd		:in std_logic;
	drv0hdi		:in std_logic;		--IBM 1.44MB format
	drv1hd		:in std_logic;
	drv1hdi		:in std_logic;		--IBM 1.44MB format
	
	drv0hds		:out std_logic;
	drv1hds		:out std_logic;
	
	drv0int		:out integer range 0 to (BR_300_D*sysclk/1000000);
	drv1int		:out integer range 0 to (BR_300_D*sysclk/1000000);
	
	hmssft		:out std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);
end component;

component FDC
generic(
	maxtrack	:integer	:=85;
	maxbwidth	:integer	:=88;
	rdytout		:integer	:=800;
	preseek		:std_logic	:='0';
	sysclk		:integer	:=20
);
port(
	RDn		:in std_logic;
	WRn		:in std_logic;
	CSn		:in std_logic;
	A0		:in std_logic;
	WDAT	:in std_logic_vector(7 downto 0);
	RDAT	:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	DACKn	:in std_logic;
	DRQ		:out std_logic;
	TC		:in std_logic;
	INTn	:out std_logic;
	WAITIN	:in std_logic	:='0';

	WREN	:out std_logic;		--pin24
	WRBIT	:out std_logic;		--pin22
	RDBIT	:in std_logic;		--pin30
	STEP	:out std_logic;		--pin20
	SDIR	:out std_logic;		--pin18
	WPRT	:in std_logic;		--pin28
	track0	:in std_logic;		--pin26
	index	:in std_logic;		--pin8
	side	:out std_logic;		--pin32
	usel	:out std_logic_vector(1 downto 0);
	READY	:in std_logic;		--pin34
	
	int0	:in integer range 0 to maxbwidth;
	int1	:in integer range 0 to maxbwidth;
	int2	:in integer range 0 to maxbwidth;
	int3	:in integer range 0 to maxbwidth;
	
	td0		:in std_logic;
	td1		:in std_logic;
	td2		:in std_logic;
	td3		:in std_logic;
	hmssft	:in std_logic;		--0.5msec
	
	busy	:out std_logic;
	mfm	:out std_logic;
	
	mon0	:out std_logic_vector(7 downto 0);
	mon1	:out std_logic_vector(7 downto 0);
	mon2	:out std_logic_vector(7 downto 0);
	mon3	:out std_logic_vector(7 downto 0);
	mon4	:out std_logic_vector(7 downto 0);
	mon5	:out std_logic_vector(7 downto 0);
	mon6	:out std_logic_vector(7 downto 0);
	mon7	:out std_logic_vector(7 downto 0);

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component dskchk2d
generic(
	sysclk	:integer	:=20000;	--system clock(kHz)	20000
	chkint	:integer	:=300;		--check interval(msec)
	signwait:integer	:=1;		--signal wait length(usec)
	datwait	:integer	:=10;		--data wait length(usec)
	motordly:integer	:=500		--motor rotate delay(msec)	
);
port(
	FDC_USELn	:in std_logic_vector(1 downto 0);
	FDC_BUSY	:in std_logic;
	FDC_MOTORn	:in std_logic_vector(1 downto 0);
	FDC_DIRn	:in std_logic;
	FDC_STEPn	:in std_logic;
	FDC_READYn	:out std_logic;
	FDC_WAIT	:out std_logic;
	
	FDD_USELn	:out std_logic_vector(1 downto 0);
	FDD_MOTORn	:out std_logic_vector(1 downto 0);
	FDD_DATAn	:in std_logic;
	FDD_INDEXn	:in std_logic;
	FDD_DSKCHGn	:in std_logic;
	FDD_DIRn	:out std_logic;
	FDD_STEPn	:out std_logic;
	
	driveen		:in std_logic_vector(1 downto 0)	:=(others=>'1');
	f_eject		:in std_logic_vector(1 downto 0)	:=(others=>'0');
	
	indisk		:out std_logic_vector(1 downto 0);
	
	hmssft		:in std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);	
end component;

component FDDIBM
port(
	CS	:in std_logic;
	RD	:in std_logic;
	WR	:in std_logic;
	
	WRDAT	:in std_logic_vector(7 downto 0);
	RDDAT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	
	DSn		:in std_logic_vector(1 downto 0);
	DENn	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component intchk
generic(
	interval	:integer	:=100;
	chk			:integer	:=10
);
port(
	en			:out std_logic;
	clk			:in std_logic;
	rstn		:in std_logic
);
end component;

component fixtimer
generic(
	timerlen	:integer	:=200;
	pulsewidth	:integer	:=2
);
port(
	start	:in std_logic;
	sft		:in std_logic;
	
	pulse	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component  OPN
generic(
	res		:integer	:=9
);
port(
	DIN		:in std_logic_vector(7 downto 0);
	DOUT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	CSn		:in std_logic;
	ADR0	:in std_logic;
	RDn		:in std_logic;
	WRn		:in std_logic;
	INTn	:out std_logic;
	
	snd		:out std_logic_vector(res-1 downto 0);
	
	PAOUT	:out std_logic_vector(7 downto 0);
	PAIN	:in std_logic_vector(7 downto 0);
	PAOE	:out std_logic;
	
	PBOUT	:out std_logic_vector(7 downto 0);
	PBIN	:in std_logic_vector(7 downto 0);
	PBOE	:out std_logic;

	clk		:in std_logic;
	cpuclk	:in std_logic;
	sft		:in std_logic;
	rstn	:in std_logic
);
end component;

component OPNA
generic(
	res		:integer	:=16
);
port(
	DIN		:in std_logic_vector(7 downto 0);
	DOUT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	CSn		:in std_logic;
	ADR		:in std_logic_vector(1 downto 0);
	RDn		:in std_logic;
	WRn		:in std_logic;
	INTn	:out std_logic;
	
	sndL		:out std_logic_vector(res-1 downto 0);
	sndR		:out std_logic_vector(res-1 downto 0);
	sndPSG		:out std_logic_vector(res-1 downto 0);
	
	PAOUT	:out std_logic_vector(7 downto 0);
	PAIN	:in std_logic_vector(7 downto 0);
	PAOE	:out std_logic;
	
	PBOUT	:out std_logic_vector(7 downto 0);
	PBIN	:in std_logic_vector(7 downto 0);
	PBOE	:out std_logic;
	
	RAMADDR	:out std_logic_vector(17 downto 0);
	RAMRD	:out std_logic;
	RAMWR	:out std_logic;
	RAMRDAT	:in std_logic_vector(7 downto 0);
	RAMWDAT	:out std_logic_vector(7 downto 0);
	RAMWAIT	:in std_logic;

	clk		:in std_logic;
	cpuclk	:in std_logic;
	sft		:in std_logic;
	rstn	:in std_logic
);
end component;

component GRAGDC
port(
	CS		:in std_logic;
	ADDR	:in std_logic_vector(1 downto 0);
	RD		:in std_logic;
	WR		:in std_logic;
	DIN		:in std_logic_vector(7 downto 0);
	DOUT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	
	LPEND	:in std_logic;
	VRTC	:in std_logic;
	HRTC	:in std_logic;
	
	VRAMSEL	:out std_logic;
	CRAMSEL	:out std_logic;
	
	GRAPHEN		:out std_logic;
	VZOOM		:out std_logic_vector(3 downto 0);
	BASEADDR0	:out std_logic_vector(17 downto 0);
	BASEADDR1	:out std_logic_vector(17 downto 0);
	SL0			:out std_logic_vector(9 downto 0);
	SL1			:out std_logic_vector(9 downto 0);
	IM			:out std_logic;
	PITCH		:out std_logic_vector(7 downto 0);
	DOTPLINE	:out std_logic_vector(4 downto 0);
	
	GDC_ADDR	:out std_logic_vector(17 downto 0);
	GDC_RDAT	:in std_logic_vector(15 downto 0);
	GDC_WDAT	:out std_logic_vector(15 downto 0);
	GDC_RD		:out std_logic;
	GDC_WR		:out std_logic;
	GDC_MACK		:in std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component TXTGDC
port(
	CS		:in std_logic;
	ADDR	:in std_logic_vector(2 downto 0);
	RD		:in std_logic;
	WR		:in std_logic;
	DIN		:in std_logic_vector(7 downto 0);
	DOUT	:out std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	
	LPEND	:in std_logic;
	VRTC	:in std_logic;
	HRTC	:in std_logic;
	
	ATRSEL		:out std_logic;
	C40			:out std_logic;
	GRMONO		:out std_logic;
	FONTSEL		:out std_logic;
	GRPMODE		:out std_logic;
	KACMODE		:out std_logic;
	NVMWPROT	:out std_logic;
	DISPEN		:out std_logic;
	COLORMODE	:out std_logic;
	EGCEN		:out std_logic;
	GDCCLK		:out std_logic;
	GDCCLK2		:out std_logic;
	CUREN		:out std_logic;
	CHARLINES	:out std_logic_vector(4 downto 0);
	BLRATE		:out std_logic_vector(4 downto 0);
	CURBLINK	:out std_logic;
	CURUPPER	:out std_logic_vector(4 downto 0);
	CURLOWER	:out std_logic_vector(4 downto 0);
	VIDEN		:out std_logic;
	SAD0		:out std_logic_vector(12 downto 0);
	SAD1		:out std_logic_vector(12 downto 0);
	SAD2		:out std_logic_vector(12 downto 0);
	SAD3		:out std_logic_vector(12 downto 0);
	SL0			:out std_logic_vector(9 downto 0);
	SL1			:out std_logic_vector(9 downto 0);
	SL2			:out std_logic_vector(9 downto 0);
	SL3			:out std_logic_vector(9 downto 0);
	PITCH		:out std_logic_vector(7 downto 0);
	EAD			:out std_logic_vector(12 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component ppi8255 is
port(
	CSn		:in std_logic;
	RDn		:in std_logic;
	WRn		:in std_logic;
	ADR		:in std_logic_vector(1 downto 0);
	DATIN	:in std_logic_vector(7 downto 0);
	DATOUT	:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	
	PAi		:in std_logic_vector(7 downto 0);
	PAo		:out std_logic_vector(7 downto 0);
	PAoe	:out std_logic;
	PBi		:in std_logic_vector(7 downto 0);
	PBo		:out std_logic_vector(7 downto 0);
	PBoe	:out std_logic;
	PCHi	:in std_logic_vector(3 downto 0);
	PCHo	:out std_logic_vector(3 downto 0);
	PCHoe	:out std_logic;
	PCLi	:in std_logic_vector(3 downto 0);
	PCLo	:out std_logic_vector(3 downto 0);
	PCLoe	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component e8251
port(
	WRn		:in std_logic;
	RDn		:in std_logic;
	C_Dn	:in std_logic;
	CSn		:in std_logic;
	DATIN	:in std_logic_vector(7 downto 0);
	DATOUT	:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	INTn	:out std_logic;
	
	TXD		:out std_logic;
	RxD		:in std_logic;
	
	DSRn	:in std_logic;
	DTRn	:out std_logic;
	RTSn	:out std_logic;
	CTSn	:in std_logic;
	
	TxRDY	:out std_logic;
	TxEMP	:out std_logic;
	RxRDY	:out std_logic;
	
	TxCn	:in std_logic;
	RxCn	:in std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component ITFSW
port(
	CS		:in std_logic;
	WR		:in std_logic;
	DIN		:in std_logic_vector(7 downto 0);
	
	ITFEN	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component deltasigmas
	generic(
		width	:integer	:=8
	);
	port(
		data	:in	std_logic_vector(width-1 downto 0);
		datum	:out std_logic;
		
		sft		:in std_logic;
		clk		:in std_logic;
		rstn	:in std_logic
	);
end component;

component DIGIFILTER
	generic(
		TIME	:integer	:=2;
		DEF		:std_logic	:='0'
	);
	port(
		D	:in std_logic;
		Q	:out std_logic;

		clk	:in std_logic;
		rstn :in std_logic
	);
end component;

component UNCHCHATA
	generic(
		MASKTIME	:integer	:=200;	--usec
		SYS_CLK		:integer	:=20	--MHz
	);
	port(
		SRC		:in std_logic;
		DST		:out std_logic;
		
		clk		:in std_logic;
		rstn	:in std_logic
	);
end component;

component e8255
generic(
	deflogic	:std_logic	:='0'
);
port(
	CSn		:in std_logic;
	RDn		:in std_logic;
	WRn		:in std_logic;
	ADR		:in std_logic_vector(1 downto 0);
	DATIN	:in std_logic_vector(7 downto 0);
	DATOUT	:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	
	PAi		:in std_logic_vector(7 downto 0);
	PAo		:out std_logic_vector(7 downto 0);
	PAoe	:out std_logic;
	PBi		:in std_logic_vector(7 downto 0);
	PBo		:out std_logic_vector(7 downto 0);
	PBoe	:out std_logic;
	PCHi	:in std_logic_vector(3 downto 0);
	PCHo	:out std_logic_vector(3 downto 0);
	PCHoe	:out std_logic;
	PCLi	:in std_logic_vector(3 downto 0);
	PCLo	:out std_logic_vector(3 downto 0);
	PCLoe	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component rtc4990MiSTer
generic(
	clkfreq	:integer	:=21477270;
	YEAROFF	:std_logic_vector(7 downto 0)	:=x"00"
);
port(
	DCLK	:in std_logic;
	DIN		:in std_logic;
	DOUT	:out std_logic;
	C		:in std_logic_vector(2 downto 0);
	CS		:in std_logic;
	STB		:in std_logic;
	OE		:in std_logic;

	RTCIN	:in std_logic_vector(64 downto 0);

 	sclk	:in std_logic;
	rstn	:in std_logic
);
end component;

component  clkdiv
generic(
	dwidth	:integer	:=8
);
port(
	div		:in std_logic_vector(dwidth-1 downto 0);
	
	cout	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component KANJI1RAMDP
	PORT
	(
		address_a		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
		address_b		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
		clock_a		: IN STD_LOGIC  := '1';
		clock_b		: IN STD_LOGIC ;
		data_a		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		data_b		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		wren_a		: IN STD_LOGIC  := '0';
		wren_b		: IN STD_LOGIC  := '0';
		q_a		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		q_b		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END component;

component KANJI11RAMDP
PORT
(
	address_a		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
	address_b		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
	clock_a		: IN STD_LOGIC  := '1';
	clock_b		: IN STD_LOGIC ;
	data_a		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	data_b		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	wren_a		: IN STD_LOGIC  := '0';
	wren_b		: IN STD_LOGIC  := '0';
	q_a		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
	q_b		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
);
end component;

component GAIJIRAMDP
PORT
(
	address_a		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
	address_b		: IN STD_LOGIC_VECTOR (16 DOWNTO 0);
	clock_a		: IN STD_LOGIC  := '1';
	clock_b		: IN STD_LOGIC ;
	data_a		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	data_b		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	wren_a		: IN STD_LOGIC  := '0';
	wren_b		: IN STD_LOGIC  := '0';
	q_a		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
	q_b		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
);
end component;

component romcopy
generic(
	BGNADDR	:std_logic_vector(23 downto 0)	:=x"700000";
	ENDADDR	:std_logic_vector(23 downto 0)	:=x"7fffff";
	AWIDTH	:integer	:=20
);
port(
	addr	:out std_logic_vector(AWIDTH-1 downto 0);
	wdat	:out std_logic_vector(7 downto 0);
	aen		:out std_logic;
	wr		:out std_logic;
	ack		:in std_logic;
	done	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component DMA8237
port(
	PCS		:in std_logic;
	PADDR	:in std_logic_vector(3 downto 0);
	PRD		:in std_logic;
	PWR		:in std_logic;
	PRDATA	:out std_logic_vector(7 downto 0);
	PWDATA	:in std_logic_vector(7 downto 0);
	PDOE	:out std_logic;
	INT		:out std_logic;
	
	DREQ	:in std_logic_vector(3 downto 0);
	DACK	:out std_logic_vector(3 downto 0);
	BUSREQ	:out std_logic;
	BUSACK	:in std_logic;
	DADDR	:out std_logic_vector(15 downto 0);
	DAOE	:out std_logic;
	MEMRD	:out std_logic;
	MEMWR	:out std_logic;
	IORD	:out std_logic;
	IOWR	:out std_logic;
	IOWAIT	:in std_logic;
	IOACK	:in std_logic;
	MEMACK	:in std_logic;
	TC		:out std_logic_vector(3 downto 0);
	ACARRY	:out std_logic_vector(3 downto 0);
	CURCH	:out integer range 0 to 4;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component DMASW
port(
	cpustb	:in std_logic;
	
	dmabreq	:in std_logic;
	
	dmaen	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component DMAUADDR	is
port(
	CS		:in std_logic;
	ADDR	:in std_logic_vector(1 downto 0);
	CSMODE	:in std_logic;
	WR		:in std_logic;
	WDATA	:in std_logic_vector(7 downto 0);
	
	CURCH	:in integer range 0 to 4;
	CARRY	:in std_logic_vector(3 downto 0);
	ADDRU	:out std_logic_vector(7 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component PTC8253
port(
	CS		:in std_logic;
	ADDR	:in std_logic_vector(1 downto 0);
	RD		:in std_logic;
	WR		:in std_logic;
	RDAT	:out std_logic_vector(7 downto 0);
	WDAT	:in std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	
	CNTIN	:in std_logic_vector(2 downto 0);
	TRIG	:in std_logic_vector(2 downto 0);
	CNTOUT	:out std_logic_vector(2 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component nvram98
port(
	addr	:in std_logic_vector(2 downto 0);
	cs		:in std_logic;
	wrdat	:in std_logic_vector(7 downto 0);
	wr		:in std_logic;
	rd		:in std_logic;
	wprot	:in std_logic;
	rddat	:out std_logic_vector(7 downto 0);
	ack		:out std_logic;
	
	clk		:in std_logic;
	mrstn	:in std_logic;
	rstn	:in std_logic
);
end component;

component KNJRAMCONT
generic(
	LDR_AWIDTH	:integer	:=19;
	LDR_BGNADDR	:std_logic_vector(23 downto 0)	:=x"040000"
);
port(
	LDR_ADDR	:in std_logic_vector(LDR_AWIDTH-1 downto 0);
	LDR_EN		:in std_logic;
	LDR_WR		:in std_logic;
	LDR_WDAT	:in std_logic_vector(7 downto 0);
	
	ioaddr		:in std_logic_vector(15 downto 0);
	iowr		:in std_logic;
	iord		:in std_logic;
	wrdat		:in std_logic_vector(7 downto 0);

	KNJRAMSEL	:out std_logic_vector(1 downto 0);
	KNJRAMADDR	:out std_logic_vector(16 downto 0);
	KNJRAMWDAT	:out std_logic_vector(7 downto 0);
	KNJRAMWR	:out std_logic;
	KNJRAMOE	:out std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);
end component;

component  IO_WR
generic(
	IOADR	:in std_logic_vector(15 downto 0)	:=x"0000"
);
port(
	ADR		:in std_logic_vector(15 downto 0);
	WR		:in std_logic;
	DAT		:in std_logic_vector(7 downto 0);
	
	bit7	:out std_logic;
	bit6	:out std_logic;
	bit5	:out std_logic;
	bit4	:out std_logic;
	bit3	:out std_logic;
	bit2	:out std_logic;
	bit1	:out std_logic;
	bit0	:out std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component IO_RD
generic(
	IOADR	:in std_logic_vector(15 downto 0)	:=x"0000"
);
port(
	ADR		:in std_logic_vector(15 downto 0);
	RD		:in std_logic;
	DATOUT	:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	
	bit7	:in std_logic;
	bit6	:in std_logic;
	bit5	:in std_logic;
	bit4	:in std_logic;
	bit3	:in std_logic;
	bit2	:in std_logic;
	bit1	:in std_logic;
	bit0	:in std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component IO_RW
generic(
	IOADR		:std_logic_vector(15 downto 0)	:=x"0000";
	RSTVAL	:std_logic_vector(7 downto 0)		:=x"00"
);
port(
	ADR		:in std_logic_vector(15 downto 0);
	RD		:in std_logic;
	WR		:in std_logic;
	DATIN	:in std_logic_vector(7 downto 0);
	DATOUT	:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	
	bit7	:out std_logic;
	bit6	:out std_logic;
	bit5	:out std_logic;
	bit4	:out std_logic;
	bit3	:out std_logic;
	bit2	:out std_logic;
	bit1	:out std_logic;
	bit0	:out std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component IO_RDP is
port(
	CS		:in std_logic;
	RD		:in std_logic;
	DATOUT:out std_logic_vector(7 downto 0);
	DATOE	:out std_logic;
	
	bit7	:in std_logic;
	bit6	:in std_logic;
	bit5	:in std_logic;
	bit4	:in std_logic;
	bit3	:in std_logic;
	bit2	:in std_logic;
	bit1	:in std_logic;
	bit0	:in std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component IO_WRP is
port(
	CS		:in std_logic;
	WR		:in std_logic;
	DAT	:in std_logic_vector(7 downto 0);
	
	bit7	:out std_logic;
	bit6	:out std_logic;
	bit5	:out std_logic;
	bit4	:out std_logic;
	bit3	:out std_logic;
	bit2	:out std_logic;
	bit1	:out std_logic;
	bit0	:out std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component pseudoide
port(
	ioaddr	:in std_logic_Vector(15 downto 0);
	iord	:in std_logic;
	iowr	:in std_logic;
	rddat	:out std_logic_vector(15 downto 0);
	wrdat	:in std_logic_vector(15 downto 0);
	doe		:out std_logic;
	int		:out std_logic;
	
	curdrive	:out std_logic;
	sectcount	:out std_logic_vector(7 downto 0);
	sectnum		:out std_logic_vector(7 downto 0);
	cyl			:out std_logic_vector(15 downto 0);
	dsel		:out std_logic;
	head		:out std_logic_vector(3 downto 0);
	
	command		:out std_logic_vector(7 downto 0);
	commandwr	:out std_logic;
	commanddone	:in std_logic;
	driveconnect:in std_logic_vector(1 downto 0);
	seekdone	:in std_logic;
	drvready	:in std_logic;
	datareq		:in std_logic;
	drvwrite	:in std_logic;
	drvindex	:in std_logic;
	drverror	:in std_logic_vector(7 downto 0);
	drvrddat	:in std_logic_vector(15 downto 0);
	drvwrdat	:out std_logic_vector(15 downto 0);
	drvrd		:out std_logic;
	drvwr		:out std_logic;
	drvrst		:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component idedrv
port(
	command		:in std_logic_vector(7 downto 0);
	command_wr	:in std_logic;
	command_ack	:out std_logic;
	rddat		:out std_logic_vector(15 downto 0);
	rd			:in std_logic;
	wrdat		:in std_logic_vector(15 downto 0);
	wr			:in std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);
end component;

component tstamp
generic(
	sysclk	:integer 	:=20000;	--kHz
	unit	:integer	:=3260		--nsec
);
port(
	addr	:in std_logic;
	ce		:in std_logic;
	rd		:in std_logic;
	wr		:in std_logic;
	rddat	:out std_logic_vector(15 downto 0);
	doe		:out std_logic;
	waitn	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;


component SFTCLK
generic(
	SYS_CLK	:integer	:=20000;
	OUT_CLK	:integer	:=1600;
	selWIDTH :integer	:=2
);
port(
	sel		:in std_logic_vector(selWIDTH-1 downto 0);
	SFT		:out std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component diskbios
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		q		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
END component;

component diskemu_mister
generic(
	fclkfreq		:integer	:=30000;
	sclkfreq		:integer	:=10000;
	fdwait	:integer	:=10
);
port(

--SASI
	sasi_din	:in std_logic_vector(7 downto 0)	:=(others=>'0');
	sasi_dout	:out std_logic_vector(7 downto 0);
	sasi_sel	:in std_logic						:='0';
	sasi_bsy	:out std_logic;
	sasi_req	:out std_logic;
	sasi_ack	:in std_logic						:='0';
	sasi_io		:out std_logic;
	sasi_cd		:out std_logic;
	sasi_msg	:out std_logic;
	sasi_rst	:in std_logic						:='0';

--FDD
	fdc_useln	:in std_logic_vector(1 downto 0)	:=(others=>'1');
	fdc_motorn	:in std_logic_vector(1 downto 0)	:=(others=>'1');
	fdc_readyn	:out std_logic;
	fdc_wrenn	:in std_logic						:='1';
	fdc_wrbitn	:in std_logic						:='1';
	fdc_rdbitn	:out std_logic;
	fdc_stepn	:in std_logic						:='1';
	fdc_sdirn	:in std_logic						:='1';
	fdc_track0n	:out std_logic;
	fdc_indexn	:out std_logic;
	fdc_siden	:in std_logic						:='1';
	fdc_wprotn	:out std_logic;
	fdc_eject	:in std_logic_vector(1 downto 0)	:=(others=>'0');
	fdc_indisk	:out std_logic_vector(1 downto 0)	:=(others=>'0');
	fdc_trackwid:in std_logic						:='1';	--1:2HD/2DD 0:2D
	fdc_dencity	:in std_logic						:='1';	--1:2HD 0:2DD/2D
	fdc_rpm		:in std_logic						:='0';	--1:360rpm 0:300rpm
	fdc_mfm		:in std_logic						:='1';
	
--FD emulator
	fde_tracklen:out std_logic_vector(13 downto 0);
	fde_ramaddr	:out std_logic_vector(22 downto 0);
	fde_ramrdat	:in std_logic_vector(15 downto 0);
	fde_ramwdat	:out std_logic_vector(15 downto 0);
	fde_ramwr	:out std_logic;
	fde_ramwait	:in std_logic;
	fec_ramaddrh :out std_logic_vector(14 downto 0);
	fec_ramaddrl :in std_logic_vector(7 downto 0);
	fec_ramwe	:in std_logic;
	fec_ramrdat	:out std_logic_vector(15 downto 0);
	fec_ramwdat	:in std_logic_vector(15 downto 0);
	fec_ramrd	:out std_logic;
	fec_ramwr	:out std_logic;
	fec_rambusy	:in std_logic;

	fec_fdsync	:in std_logic_Vector(1 downto 0);

--SRAM
	sram_cs		:in std_logic						:='0';
	sram_addr	:in std_logic_vector(12 downto 0)	:=(others=>'0');
	sram_rdat	:out std_logic_vector(15 downto 0);
	sram_wdat	:in std_logic_vector(15 downto 0)	:=(others=>'0');
	sram_rd		:in std_logic						:='0';
	sram_wr		:in std_logic_vector(1 downto 0)	:="00";
	sram_wp		:in std_logic						:='0';
	
	sram_ld		:in std_logic;
	sram_st		:in std_logic;

--MiSTer
	mist_mounted	:in std_logic_vector(3 downto 0);	--SRAM & HDD & FDD1 &FDD0
	mist_readonly	:in std_logic_vector(3 downto 0);
	mist_imgsize	:in std_logic_vector(63 downto 0);

	mist_lba		:out std_logic_vector(31 downto 0);
	mist_rd			:out std_logic_vector(3 downto 0);
	mist_wr			:out std_logic_vector(3 downto 0);
	mist_ack		:in std_logic;

	mist_buffaddr	:in std_logic_vector(8 downto 0);
	mist_buffdout	:in std_logic_vector(7 downto 0);
	mist_buffdin	:out std_logic_vector(7 downto 0);
	mist_buffwr		:in std_logic;
	
--common
	initdone	:out std_logic;
	busy		:out std_logic;
	fclk		:in std_logic;
	sclk		:in std_logic;
	rclk		:in std_logic;
	rstn		:in std_logic
);
end component;

component FECcont
generic(
	SDRAWIDTH	:integer	:=22
);
port(
	HIGHADDR	:in std_logic_vector(15 downto 0);
	BUFADDR		:out std_logic_vector(7 downto 0);
	RD			:in std_logic;
	WR			:in std_logic;
	RDDAT		:out std_logic_vector(15 downto 0);
	WRDAT		:in std_logic_vector(15 downto 0);
	BUFRD		:out std_logic;
	BUFWR		:out std_logic;
	BUFWAIT		:in std_logic;
	BUSY		:out std_logic;
	
	SDR_ADDR	:out std_logic_vector(SDRAWIDTH-1 downto 0);
	SDR_RD		:out std_logic;
	SDR_WR		:out std_logic;
	SDR_RDAT	:in std_logic_vector(15 downto 0);
	SDR_WDAT	:out std_logic_vector(15 downto 0);
	SDR_WAIT	:in std_logic;
	
	clk			:in std_logic;
	rstn		:in std_logic
);
end component;

component MOUSECONV
generic(
	CLKCYC	:integer	:=20000;
	SFTCYC	:integer	:=400
);
port(
	HC		:in std_logic;
	SXY		:in std_logic;
	SHL		:in std_logic;

	MOUSDAT	:out std_logic_vector(7 downto 0);

	MCLKIN	:in std_logic;
	MCLKOUT:out std_logic;
	MDATIN	:in std_logic;
	MDATOUT:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component mouseint
generic(
	SYSFREQ	:integer	:=20000
);
port(
	cs		:in std_logic;
	wr		:in std_logic;
	wrdat	:in std_logic_vector(7 downto 0);
	
	int		:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component grpal
generic (VIDEO_STAGED : boolean := false);
port(
	CS			:in std_logic;
	ADDR		:in std_logic_vector(1 downto 0);
	WR			:in std_logic;
	RD			:in std_logic;
	WRDAT		:in std_logic_vector(7 downto 0);
	RDDAT		:out std_logic_vector(7 downto 0);
	DOE			:out std_logic;
	
	COLORMODE	:in std_logic;
	NUMIN		:in std_logic_vector(3 downto 0);
	vidR		:out std_logic_vector(3 downto 0);
	vidG		:out std_logic_vector(3 downto 0);
	vidB		:out std_logic_vector(3 downto 0);
	
	clk			:in std_logic;
	rstn		:in std_logic;
    video_clk : in std_logic := '0'
);
end component;

component sndid
generic(
	ID		:std_logic_vector(3 downto 0)	:=x"f"
);

port(
	CS		:in std_logic;
	RD		:in std_logic;
	WR		:in std_logic;
	
	RDDAT	:out std_logic_vector(7 downto 0);
	DOE	:out std_logic;
	WRDAT	:in std_logic_vector(7 downto 0);
	
	OPNAMSK	:out std_logic;
	OPNAEXT	:out std_logic;
	
	clk	:in std_logic;
	rstn	:in std_logic
);
end component;

component average
generic(
	datwidth	:integer	:=16
);
port(
	INA		:in std_logic_vector(datwidth-1 downto 0);
	INB		:in std_logic_vector(datwidth-1 downto 0);
	
	OUTQ	:out std_logic_vector(datwidth-1 downto 0)
);
end component;

--clocks and resets
signal	drstn	:std_logic;
signal	srstn	:std_logic;
signal	mrstn	:std_logic;
signal	irstn	:std_logic;
signal	vrstn	:std_logic;
signal video_logic_rstn :std_logic;
signal	grpclk	:std_logic;

--text ram
--(cpu side)
signal	tramcs		:std_logic;
signal	tramaddr	:std_logic_vector(11 downto 0);
signal	tramdo		:std_logic_vector(15 downto 0);
signal	tramdoe		:std_logic_vector(1 downto 0);
signal	tramack		:std_logic;
signal	aramcs		:std_logic;
signal	aramaddr	:std_logic_vector(11 downto 0);
signal	aramdo		:std_logic_vector(15 downto 0);
signal	aramdoew	:std_logic_vector(1 downto 0);
signal	aramdoe		:std_logic_vector(1 downto 0);
signal	aramack		:std_logic;
--(video side)
signal	vaddr		:std_logic_vector(12 downto 0);
signal	vtdat		:std_logic_vector(15 downto 0);
signal	vadat		:std_logic_vector(7 downto 0);
signal	vadatw		:std_logic_vector(15 downto 0);

--SDRAM
-- cpu side bus
signal	CB_BANK		:std_logic_vector(1 downto 0);
signal	CB_ADDR		:std_logic_vector(21 downto 0);
signal	CB_RDAT0	:std_logic_vector(15 downto 0);
signal	CB_RDAT1	:std_logic_vector(15 downto 0);
signal	CB_RDAT2	:std_logic_vector(15 downto 0);
signal	CB_RDAT3	:std_logic_vector(15 downto 0);
signal	CB_WDAT0	:std_logic_vector(15 downto 0);
signal	CB_WDAT1	:std_logic_vector(15 downto 0);
signal	CB_WDAT2	:std_logic_vector(15 downto 0);
signal	CB_WDAT3	:std_logic_vector(15 downto 0);
signal	CB_WR1		:std_logic;
signal	CB_WR4		:std_logic;
signal	CB_RD1		:std_logic;
signal	CB_RD4		:std_logic;
signal	CB_RMW1		:std_logic;
signal	CB_RMW4		:std_logic;
signal	CB_BSEL		:std_logic_vector(1 downto 0);
signal	CB_PSEL		:std_logic_vector(3 downto 0);
signal	CB_ACK		:std_logic;
signal	MEM_INIDONE	:std_logic;
-- video side bus
signal	GRAMADR	:std_logic_vector(21 downto 0);
signal	GRAMRD	:std_logic;
signal	GRAMACK	:std_logic;
signal	GRDAT0	:std_logic_vector(15 downto 0);
signal	GRDAT1	:std_logic_vector(15 downto 0);
signal	GRDAT2	:std_logic_vector(15 downto 0);
signal	GRDAT3	:std_logic_vector(15 downto 0);

--CPU bus
signal	cpuaddr	:std_logic_vector(19 downto 1);
signal	cpusel	:std_logic_Vector(1 downto 0);
signal	cpuod	:std_logic_vector(15 downto 0);
signal	cpuoe	:std_logic;
signal	tga		:std_logic;
signal	ack		:std_logic;
signal	stb		:std_logic;
signal	cyc		:std_logic;
signal	tgc		:std_logic;
signal	tgca	:std_logic;
signal	nmi		:std_logic;
signal	nmia	:std_logic;
signal	monpc	:std_logic_vector(19 downto 0);
signal	cpuack	:std_logic;
signal	cpu_iord	:std_logic;
signal	cpu_iowr	:std_logic;
signal	cpu_dbus	:std_logic_vector(15 downto 0);

--DMA
signal	DMA_CS	:std_logic;
signal	DMA_ODAT:std_logic_vector(7 downto 0);
signal	DMA_DOE	:std_logic;
signal	DMA_OADR:std_logic_vector(15 downto 0);
signal	DMA_AOE	:std_logic;
signal	DMAen	:std_logic;
signal	MEMack	:std_logic;
signal	DMA_H2L	:std_logic;
signal	DMA_L2H	:std_logic;
signal	DMA_REQ	:std_logic_vector(3 downto 0);
signal	DMA_ACK	:std_logic_vector(3 downto 0);
signal	DMA_TC	:std_logic_vector(3 downto 0);
signal	DMA_ACARRY	:std_logic_vector(3 downto 0);
signal	DMA_BREQ:std_logic;
signal	DMA_BACK:std_logic;
signal	DMA_MRD	:std_logic;
signal	DMA_MWR	:std_logic;
signal	DMA_IORD	:std_logic;
signal	DMA_IOWR	:std_logic;
signal	DMAsel	:std_logic_vector(1 downto 0);
signal	DMA_UADRw:std_logic_vector(7 downto 0);
signal	DMA_UADR:std_logic_vector(3 downto 0);
signal	DMA_CURCH:integer range 0 to 4;
signal	DMAU_CS	:std_logic;
signal	DMAUM_CS:std_logic;

--general bus
signal	abus	:std_logic_vector(19 downto 1);
signal	dbus	:std_logic_vector(15 downto 0);
signal io_wdata :std_logic_vector(15 downto 0);
signal mem_wdata :std_logic_vector(15 downto 0);
signal fdc_wdata :std_logic_vector(7 downto 0);
signal dma_mem_high, dma_mem_low :std_logic_vector(8 downto 0);
signal dbus_high, dbus_low :std_logic_vector(8 downto 0);
signal cache_invalidate :std_logic;
signal	bussel	:std_logic_vector(1 downto 0);

--io port
signal	ioaddr	:std_logic_vector(15 downto 0);
signal ioaddr_even, ioaddr_odd :std_logic_vector(15 downto 0);
signal	iord	:std_logic;
signal	iowr	:std_logic;
signal	iowaitn	:std_logic;
signal	iack	:std_logic;

--memory bus
signal	MSD_CS	:std_logic;
signal	MBANK	:std_logic_vector(1 downto 0);
signal	MADDR	:std_logic_vector(21 downto 0);
signal	MRD		:std_logic;
signal	MWR		:std_logic;

--memory map
signal	BNK89_SEL	:std_logic_vector(7 downto 0);
signal	BNK89_ODAT	:std_logic_vector(7 downto 0);
signal	BNK89_DOE	:std_logic;
signal	BNKAB_SEL	:std_logic_vector(7 downto 0);
signal	BNKAB_ODAT	:std_logic_vector(7 downto 0);
signal	BNKAB_DOE	:std_logic;
signal	BIOSRAM		:std_logic;
signal	IDEBIOSEN	:std_logic;
signal	SCSIBIOSEN	:std_logic;
signal	SASIBIOSEN	:std_logic;
signal	SNDBIOSEN	:std_logic;
--IO0439(memory bank select)
signal	IO043F_CS	:std_logic;
signal	NECEMSSEL	:std_logic;

--GDC bus
signal	GDC_ADDR	:std_logic_vector(17 downto 0);
signal	GDC_RDAT	:std_logic_vector(15 downto 0);
signal	GDC_WDAT	:std_logic_vector(15 downto 0);
signal	GDC_RD		:std_logic;
signal	GDC_WR		:std_logic;
signal	GDC_RAMBANK	:std_logic_vector(1 downto 0);
signal	GDC_RAMADDR	:std_logic_vector(21 downto 0);
signal	GDC_RAMACK	:std_logic;

--GRCG GDC bus
signal	GCG_GDC_RD1	:std_logic;
signal	GCG_GDC_RD4	:std_logic;
signal	GCG_GDC_WR1	:std_logic;
signal	GCG_GDC_WR4	:std_logic;
signal	GCG_GDC_RMW1	:std_logic;
signal	GCG_GDC_RMW4	:std_logic;
signal	GCG_GDC_RDAT0	:std_logic_vector(15 downto 0);
signal	GCG_GDC_RDAT1	:std_logic_vector(15 downto 0);
signal	GCG_GDC_RDAT2	:std_logic_vector(15 downto 0);
signal	GCG_GDC_RDAT3	:std_logic_vector(15 downto 0);
signal	GCG_GDC_WDAT0	:std_logic_vector(15 downto 0);
signal	GCG_GDC_WDAT1	:std_logic_vector(15 downto 0);
signal	GCG_GDC_WDAT2	:std_logic_vector(15 downto 0);
signal	GCG_GDC_WDAT3	:std_logic_vector(15 downto 0);
signal GCG_GDC_WMASK :std_logic_vector(15 downto 0);
signal	GCG_GDC_WPSEL	:std_logic_vector(3 downto 0);

--interrupt controller
signal	INTM_CS		:std_logic;
signal	INTM_ODAT	:std_logic_vector(7 downto 0);
signal	INTM_OE		:std_logic;
signal	INTM		:std_logic;
signal	INTCAS		:std_logic_vector(2 downto 0);
signal	INTS_CS		:std_logic;
signal	INTS_ODAT	:std_logic_vector(7 downto 0);
signal	INTS_OE		:std_logic;
signal	INTS		:std_logic;
signal	IR10		:std_logic;
signal	IR11		:std_logic;
signal	IR12		:std_logic;
signal	IR13		:std_logic;

--Video
signal	VID_KNJADDR	:std_logic_vector(16 downto 0);
signal	VID_FNTDAT	:std_logic_vector(7 downto 0);
signal	VID_KNJ0DAT	:std_logic_vector(7 downto 0);
signal	VID_KNJ1DAT	:std_logic_vector(7 downto 0);
signal	VID_KNJ2DAT	:std_logic_vector(7 downto 0);
signal	VID_KNJSEL	:std_logic_vector(1 downto 0);
signal	GADDR		:std_logic_vector(13 downto 0);
signal	VRTC		:std_logic;
signal	HRTC		:std_logic;
signal VRTC_video, HRTC_video : std_logic;
signal	GLOWBLK		:std_logic;
signal	VidR4		:std_logic_vector(3 downto 0);
signal	VidG4		:std_logic_vector(3 downto 0);
signal	VidB4		:std_logic_vector(3 downto 0);

--GDC
signal	tGDCcs		:std_logic;
signal	tGDCod		:std_logic_vector(7 downto 0);
signal	tGDCoe		:std_logic;
signal	gGDCcs		:std_logic;
signal	gGDCod		:std_logic_vector(7 downto 0);
signal	gGDCoe		:std_logic;
signal	tGDC_C40			:std_logic;
signal	gGDC_VGRAMSEL	:std_logic;
signal	gGDC_CGRAMSEL	:std_logic;
signal	tGDC_VIDEN		:std_logic;
signal	tGDC_CUREN		:std_logic;
signal	tGDC_CHARLINES	:std_logic_vector(4 downto 0);
signal	tGDC_BLRATE		:std_logic_vector(4 downto 0);
signal	tGDC_CURBLINK	:std_logic;
signal	tGDC_CURUPPER	:std_logic_vector(4 downto 0);
signal	tGDC_CURLOWER	:std_logic_vector(4 downto 0);
signal	tGDC_iCURUPPER	:integer range 0 to 19;
signal	tGDC_iCURLOWER	:integer range 0 to 19;
signal	tGDC_BASEADDR	:std_logic_vector(12 downto 0);
signal	tGDC_PITCH		:std_logic_vector(7 downto 0);
signal	tGDC_CURADDR	:std_logic_vector(12 downto 0);
signal	tGDC_COLORMODE	:std_logic;
signal	gGDC_GRAPHEN	:std_logic;
signal	gGDC_PITCH		:std_logic_vector(7 downto 0);
signal	gGDC_DOTPLINE	:std_logic_vector(4 downto 0);
signal	gGDC_BASEADDR0	:std_logic_vector(17 downto 0);
signal	gGDC_BASEADDR1	:std_logic_vector(17 downto 0);
signal	gGDC_LINENUM0	:std_logic_vector(9 downto 0);
signal	gGDC_LINENUM1	:std_logic_vector(9 downto 0);
signal	gGDC_LINENUM	:std_logic_vector(9 downto 0);

--GRCG
signal	GCG_IOCS	:std_logic;
signal	GCG_MCS		:std_logic;
signal	GCG_ODAT	:std_logic_vector(15 downto 0);
signal	GCG_DOE		:std_logic;
signal	GCG_WR1		:std_logic;
signal	GCG_WR4		:std_logic;
signal	GCG_RD1		:std_logic;
signal	GCG_RD4		:std_logic;
signal	GCG_RMW1	:std_logic;
signal	GCG_RMW4	:std_logic;
signal GCG_WMASK, CB_PRESERVE :std_logic_vector(15 downto 0);
signal	GCG_WDAT0	:std_logic_vector(15 downto 0);
signal	GCG_WDAT1	:std_logic_vector(15 downto 0);
signal	GCG_WDAT2	:std_logic_vector(15 downto 0);
signal	GCG_WDAT3	:std_logic_vector(15 downto 0);
signal	GCG_WPSEL	:std_logic_vector(3 downto 0);

--PALETTE
signal	GPAL_CS		:std_logic;
signal	GPAL_ODAT	:std_logic_vector(7 downto 0);
signal	GPAL_DOE	:std_logic;
signal	GPAL_NO		:std_logic_vector(3 downto 0);
signal	GPAL_R		:std_logic_vector(3 downto 0);
signal	GPAL_G		:std_logic_vector(3 downto 0);
signal	GPAL_B		:std_logic_vector(3 downto 0);

--NVRAM
signal	NVR_CS		:std_logic;
signal	NVR_ADDR	:std_logic_vector(2 downto 0);
signal	NVR_WPROT	:std_logic;
signal	NVR_ODAT	:std_logic_vector(7 downto 0);
signal	NVR_WR		:std_logic;
signal	NVR_DOE		:std_logic;
signal	NVR_ACK		:std_logic;

--Programmable Timer Counter
signal	PTC_CS		:std_logic;
signal	PTC_ODAT	:std_logic_vector(7 downto 0);
signal	PTC_DOE		:std_logic;
signal	PTC_SFT		:std_logic;
signal	PTC_CNTOUT	:std_logic_vector(2 downto 0);

--printer port
signal	prncsn		:std_logic;
signal	prnod		:std_logic_vector(7 downto 0);
signal	prnoe		:std_logic;
signal	dat42		:std_logic_vector(7 downto 0);

--ITF switch
signal	ITFswcs		:std_logic;
signal	ITFen		:std_logic;

--PS/2 keyboard
signal	KBCLKIN		:std_logic;
signal	KBCLKOUT	:std_logic;
signal	KBDATIN		:std_logic;
signal	KBDATOUT	:std_logic;
signal	KBCS		:std_logic;
signal	KBod		:std_logic_vector(7 downto 0);
signal	KBoe		:std_logic;
signal	KBINT		:std_logic;

--System port(8255)
signal	SYSP_CS		:std_logic;
signal	SYSP_RDAT	:std_logic_vector(7 downto 0);
signal	SYSP_DOE	:std_logic;
signal	SYSP_PAI	:std_logic_vector(7 downto 0);
signal	SYSP_PBI	:std_logic_vector(7 downto 0);
signal	SYSP_PCI	:std_logic_vector(7 downto 0);
signal	SYSP_PAO	:std_logic_vector(7 downto 0);
signal	SYSP_PBO	:std_logic_vector(7 downto 0);
signal	SYSP_PCO	:std_logic_vector(7 downto 0);

--FDC(uPD765)
signal	FDCD_CS		:std_logic;
signal	FDCH_CS		:std_logic;
signal	FDC_CSn		:std_logic;
signal	FDC_H_Dn		:std_logic;
signal	FDC_ODAT		:std_logic_vector(7 downto 0);
signal	FDC_DOE		:std_logic;
signal	FDC_TC		:std_logic;
signal	FDC_hmssft	:std_logic;
signal	FDC_INTn		:std_logic;
signal	FDC_INTS		:std_logic;
signal	FDC_DRQ		:std_logic;
signal	FDC_DACK		:std_logic;
signal	FDC_Hsft		:std_logic;
signal	FDC_Dsft		:std_logic;
signal	FDC_sft		:std_logic;
signal	FDC_int		:integer range 0 to (BR_300_D*SYSFREQ/1000000);
signal	FDC_USEL		:std_logic_vector(1 downto 0);
signal	FDC_READY	:std_logic;
signal	FDC_BUSY		:std_logic;
signal	FDC_RESET	:std_logic;
signal	FDC_FREADY	:std_logic;
signal	FDC_DMAE		:std_logic;
signal	FDC_MOTOR	:std_logic;
signal	FDC_DIRn		:std_logic;
signal	FDC_STEPn	:std_logic;
signal	FDC_WAIT		:std_logic;


signal	FDCNT_CS		:std_logic;
signal	FDCNT_ODAT	:std_logic_vector(7 downto 0);
signal	FDCNT_DOE	:std_logic;
signal	FDCIFS_ODAT	:std_logic_vector(7 downto 0);
signal	FDCIFS_DOE	:std_logic;

signal	FDCIF_H_Dn	:std_logic;
signal	VFO_TSTART	:std_logic;
signal	VFO_INT		:std_logic;
signal	VFO_INTEN	:std_logic;

signal	FDIBM_CS	:std_logic;
signal	FDIBM_ODAT	:std_logic_vector(7 downto 0);
signal	FDIBM_DOE	:std_logic;
signal	FDIBM_DSn	:std_logic_vector(1 downto 0);

signal	FDD_USEL		:std_logic_vector(1 downto 0);
signal	FDD_MOTORn	:std_logic_vector(1 downto 0);

--Kanji RAM
signal	KNJ_ADDR	:std_logic_vector(16 downto 0);
signal	KNJ_RAMSEL	:std_logic_vector(1 downto 0);
signal	KNJ_WR		:std_logic;
signal	KNJ0_WR		:std_logic;
signal	KNJ1_WR		:std_logic;
signal	KNJ2_WR		:std_logic;
signal	KNJ_WRDAT	:std_logic_vector(7 downto 0);
signal	KNJ_DOE		:std_logic;
signal	KNJ0_ODAT	:std_logic_vector(7 downto 0);
signal	KNJ0_DOE	:std_logic;
signal	KNJ1_ODAT	:std_logic_vector(7 downto 0);
signal	KNJ1_DOE	:std_logic;
signal	KNJ2_ODAT	:std_logic_vector(7 downto 0);
signal	KNJ2_DOE	:std_logic;

--DISK(SASI) BIOS
signal	DBIO_CS		:std_logic;
signal	DBIO_ADDR	:std_logic_vector(12 downto 1);
signal	DBIO_ODAT	:std_logic_vector(15 downto 0);
signal	DBIO_DOE	:std_logic;

--pseudo IDE
signal	IDE_ODAT	:std_logic_vector(15 downto 0);
signal	IDE_DOE		:std_logic;
signal	IDE_INT		:std_logic;
signal	IDE_RDDAT	:std_logic_vector(15 downto 0);
signal	IDE_DRV_RD	:std_logic;
signal	IDE_WRDAT	:std_logic_vector(15 downto 0);
signal	IDE_DRV_WR	:std_logic;
signal	IDE_COMMAND	:std_logic_vector(7 downto 0);
signal	IDE_CMD_WR	:std_logic;
signal	IDE_CMD_ACK	:std_logic;

--RTC
signal	RTC_CCK		:std_logic;
signal	RTC_CDAT	:std_logic;
signal	RTC_CDI		:std_logic;
signal	RTC_C		:std_logic_vector(2 downto 0);
signal	RTC_CSTB	:std_logic;

--BEEP
signal	BEEPON	:std_logic;
signal	BEEP_snd	:std_logic_vector(15 downto 0);
signal	startup_muted :std_logic;

--COM
signal	COM_CS		:std_logic;
signal	COM_ODAT	:std_logic_vector(7 downto 0);
signal	COM_DOE		:std_logic;
signal	COM_INTn	:std_logic;

--IO439
signal	IO439_ODAT	:std_logic_vector(7 downto 0);
signal	IO439_DOE	:std_logic;
signal	DMA1MMASK	:std_logic;
signal	FASTLIOBIOSEN :std_logic;

--MOUSE
signal	MOUS_CS		:std_logic;
signal	MOUS_ODAT	:std_logic_vector(7 downto 0);
signal	MOUS_DOE	:std_logic;
signal	MOUS_PAIN	:std_logic_vector(7 downto 0);
signal	MOUS_PBIN	:std_logic_vector(7 downto 0);
signal	MOUS_PCHOUT	:std_logic_vector(3 downto 0);
signal	MOUS_PCLIN	:std_logic_vector(3 downto 0);
signal	MOUS_INTp	:std_logic;
signal	MOUS_INTe	:std_logic;
signal	MOUINT_CS	:std_logic;

--TIMESTAMP
signal	TSTMP_CS	:std_logic;
signal	TSTMP_ODAT	:std_logic_vector(15 downto 0);
signal	TSTMP_DOE	:std_logic;
signal	TSTMP_WAITn	:std_logic;

--Machine status
signal	IN00f0_ODAT	:std_logic_vector(7 downto 0);
signal	IN00f0_DOE	:std_logic;

--Disk emulator
signal	EMUENSW	:std_logic;
signal	lEMUENSW	:std_logic;
signal	sEMUEN	:std_logic;
signal	EMUEN	:std_logic;
signal	EMU_INIDONE	:std_logic;
signal	EMU_BUSY		:std_logic;
signal	EMU_TVADDR	:std_logic_vector(11 downto 0);
signal	EMU_TVDATA	:std_logic_vector(7 downto 0);
signal	EMU_CURL		:std_logic_vector(4 downto 0);
signal	EMU_CURC		:std_logic_vector(6 downto 0);
signal	EMU_CURE		:std_logic;
signal	EMU_KBRX		:std_logic;
signal	EMU_KBRXDAT	:std_logic_vector(7 downto 0);
signal	EMU_SDMISO	:std_logic;
signal	EMU_SDMOSI	:std_logic;
signal	EMU_SDCS		:std_logic;
signal	EMU_SDCLK	:std_logic;
signal	FDE_USEL		:std_logic_vector(1 downto 0);
signal	FDC_USELbn	:std_logic_vector(3 downto 0);
signal	FDE_READYn	:std_logic;
signal	FDE_WRENn	:std_logic;
signal	FDE_WRBITn	:std_logic;
signal	FDE_RDBITn	:std_logic;
signal	FDE_STEPn	:std_logic;
signal	FDE_SDIRn	:std_logic;
signal	FDE_TRACK0n	:std_logic;
signal	FDE_INDEXn	:std_logic;
signal	FDE_SIDEn	:std_logic;
signal	FDE_WPROTn	:std_logic;
signal	FDE_MFM		:std_logic;
signal	FDE_MOTORn	:std_logic_vector(1 downto 0);
signal	FDE_CPYBUSY	:std_logic;
signal	FDE_RAMADDR	:std_logic_vector(22 downto 0);
signal	FDE_RAMRDAT	:std_logic_vector(15 downto 0);
signal	FDE_RAMWDAT	:std_logic_vector(15 downto 0);
signal	FDE_RAMWR	:std_logic;
signal	FDE_RAMWAIT	:std_logic;
signal	FEC_RAMADDRH	:std_logic_vector(14 downto 0);
signal	FEC_RAMADDRL	:std_logic_Vector(7 downto 0);
signal	FEC_RAMRD	:std_logic;
signal	FEC_RAMWR	:std_logic;
signal	FEC_RAMWE	:std_logic;
signal	FEC_RAMRDAT	:std_logic_Vector(15 downto 0);
signal	FEC_RAMWDAT	:std_logic_Vector(15 downto 0);
signal	FEC_RAMBUSY	:std_logic;
signal	FEC_RAMWAIT	:std_logic;
signal	FEC_ADDR		:std_logic_vector(22 downto 0);
signal	FEC_RD		:std_logic;
signal	FEC_WR		:std_logic;
signal	FEC_RDAT		:std_logic_vector(15 downto 0);
signal	FEC_WDAT		:std_logic_vector(15 downto 0);

--OPN
signal	OPN_CS		:std_logic;
signal	OPN_ODAT	:std_logic_vector(7 downto 0);
signal	OPN_DOE		:std_logic;
signal	OPN_INTn		:std_logic;
signal	OPN_sndL		:std_logic_vector(15 downto 0);
signal	OPN_sndR		:std_logic_vector(15 downto 0);
signal	OPN_sndPSG	:std_logic_vector(15 downto 0);
signal	OPN_GPIOAi	:std_logic_vector(7 downto 0);
signal	OPN_GPIOAo	:std_logic_vector(7 downto 0);
signal	OPN_GPIOAoe	:std_logic;
signal	OPN_GPIOBi	:std_logic_vector(7 downto 0);
signal	OPN_GPIOBo	:std_logic_vector(7 downto 0);
signal	OPN_GPIOBoe	:std_logic;
signal	OPN_sft		:std_logic;

signal	SND_MONO		:std_logic_vector(15 downto 0);
signal	SNDID_CS		:std_logic;
signal	SNDID_ODAT	:std_logic_vector(7 downto 0);
signal	SNDID_OE		:std_logic;
signal PCM_IRQ, PCM_EXT, PCM_FM_MUTE :std_logic;
signal PCM_L, PCM_R, BASE_SND_L, BASE_SND_R :std_logic_vector(15 downto 0);
signal FM_ROUTE_L, FM_ROUTE_R, PSG_ROUTE :std_logic_vector(15 downto 0);


signal	IPCOUNT	:std_logic_vector(31 downto 0);

begin
	drstn<='1';
	mrstn<=drstn and plllock;

	ram	:SDRAMC generic map(22,100,64000/8192,true,true,true) port map(
		-- SDRAM PORTS
		PMEMCKE			=>pMemCke,
		PMEMCS_N			=>pMemCs_n,
		PMEMRAS_N		=>pMemRas_n,
		PMEMCAS_N		=>pMemCas_n,
		PMEMWE_N			=>pMemWe_n,
		PMEMUDQ			=>pMemUdq,
		PMEMLDQ			=>pMemLdq,
		PMEMBA1			=>pMemBa1,
		PMEMBA0			=>pMemBa0,
		PMEMADR			=>pMemAdr,
		PMEMDAT			=>pMemDat,

		CPUBNK			=>CB_BANK,
		CPUADR			=>CB_ADDR,
		CPURDAT0			=>CB_RDAT0,
		CPURDAT1			=>CB_RDAT1,
		CPURDAT2			=>CB_RDAT2,
		CPURDAT3			=>CB_RDAT3,
        CPUPRESERVE=>CB_PRESERVE,
		CPUWDAT0			=>CB_WDAT0,
		CPUWDAT1			=>CB_WDAT1,
		CPUWDAT2			=>CB_WDAT2,
		CPUWDAT3			=>CB_WDAT3,
		CPUWR1			=>CB_WR1,
		CPUWR4			=>CB_WR4,
		CPURD1			=>CB_RD1,
		CPURD4			=>CB_RD4,
		CPURMW1			=>CB_RMW1,
		CPURMW4			=>CB_RMW4,
		CPUBSEL			=>CB_BSEL,
		CPUPSEL			=>CB_PSEL,
		CPUACK			=>CB_ACK,
		CPUCLK			=>cpuclk,
		
		SUBBNK			=>GDC_RAMBANK,
		SUBADR			=>GDC_RAMADDR,
		SUBRDAT0			=>GCG_GDC_RDAT0,
		SUBRDAT1			=>GCG_GDC_RDAT1,
		SUBRDAT2			=>GCG_GDC_RDAT2,
		SUBRDAT3			=>GCG_GDC_RDAT3,
		SUBWDAT0			=>GCG_GDC_WDAT0,
		SUBWDAT1			=>GCG_GDC_WDAT1,
		SUBWDAT2			=>GCG_GDC_WDAT2,
		SUBWDAT3			=>GCG_GDC_WDAT3,
        SUBPRESERVE=>GCG_GDC_WMASK,
		SUBWR1			=>GCG_GDC_WR1,
		SUBWR4			=>GCG_GDC_WR4,
		SUBRD1			=>GCG_GDC_RD1,
		SUBRD4			=>GCG_GDC_RD4,
		SUBRMW1			=>GCG_GDC_RMW1,
		SUBRMW4			=>GCG_GDC_RMW4,
		SUBBSEL			=>"11",
		SUBPSEL			=>GCG_GDC_WPSEL,
		SUBACK			=>GDC_RAMACK,
		SUBCLK			=>cpuclk,
		
		VIDBNK			=>RAM_VRAMF(23 downto 22),
		VIDADR			=>GRAMADR,
		VIDDAT0			=>GRDAT0,
		VIDDAT1			=>GRDAT1,
		VIDDAT2			=>GRDAT2,
		VIDDAT3			=>GRDAT3,
		VIDRD				=>GRAMRD,
		VIDACK			=>GRAMACK,
		VIDCLK			=>grpclk,
		
		FDEADR			=>RAM_FDEMU0(23) & FDE_RAMADDR,
		FDERD				=>not FDE_RAMWR,
		FDEWR				=>FDE_RAMWR,
		FDERDAT			=>FDE_RAMRDAT,
		FDEWDAT			=>FDE_RAMWDAT,
		FDEWAIT			=>FDE_RAMWAIT,
		FDECLK			=>cpuclk,
		
		FECADR			=>RAM_FDEMU0(23) & FEC_ADDR,
		FECRD				=>FEC_RD,
		FECWR				=>FEC_WR,
		FECRDAT			=>FEC_RDAT,
		FECWDAT			=>FEC_WDAT,
		FECWAIT			=>FEC_RAMWAIT,
		FECCLK			=>cpuclk,

		
		mem_inidone		=>MEM_INIDONE,
		
		memclk			=>ramclk,
		rstn				=>mrstn
	);
	
    -- All irstn consumers use cpuclk. SDRAM ready is released in ramclk.
    memory_ready_reset : entity work.reset_release
        port map(cpuclk, rstn and MEM_INIDONE, irstn);
	
	LDR_ACK<=CB_ACK;
	
	srstn<=rstn and LDR_DONE and EMU_INIDONE;
	
	vrstn<=LDR_DONE;-- and rstn;
	video_reset : entity work.reset_release port map(vidclk,vrstn,video_logic_rstn);

	tgc<=INTM;
	
    zet_cpu: if CPU486=0 generate
	pDdrAddress<=(others=>'0'); pDdrWriteData<=(others=>'0');
	pDdrByteEnable<=(others=>'0'); pDdrBurstCount<=(others=>'0');
	pDdrRead<='0'; pDdrWrite<='0';
	cpu	:zet port map(
		wb_clk_i	=>cpuclk,
		wb_rst_i	=>not srstn,
		wb_dat_i	=>cpu_dbus,
		wb_dat_o	=>cpuod,
		wb_adr_o	=>cpuaddr,
		wb_we_o		=>cpuoe,
		wb_tga_o	=>tga,
		wb_sel_o	=>cpusel,
		wb_stb_o	=>stb,
		wb_cyc_o	=>cyc,
		wb_ack_i	=>cpuack,
		wb_tgc_i	=>tgc,
		wb_tgc_o	=>tgca,
		nmi			=>nmi,
		nmia		=>nmia,
		pc			=>monpc
	);
    end generate;

    ao486_cpu: if CPU486/=0 generate
        cpu: pc98_ao486 generic map(EXT_RAM_MB=>EXT_RAM_MB, LOWMEM_CACHE=>LOWMEM_CACHE, LOWMEM_CACHE_KB=>LOWMEM_CACHE_KB) port map(
            clk=>cpuclk, reset=>not srstn,
            interrupt_do=>INTM, interrupt_vector=>cpu_dbus(7 downto 0), interrupt_done=>tgca,
            bus_address=>cpuaddr, bus_select=>cpusel, bus_writedata=>cpuod,
            bus_write=>cpuoe, bus_strobe=>stb, bus_io=>tga,
            bus_readdata=>dbus, bus_ack=>cpuack, unmapped_access=>open,
            cache_invalidate=>cache_invalidate,
            ddr_address=>pDdrAddress, ddr_writedata=>pDdrWriteData,
            ddr_byteenable=>pDdrByteEnable, ddr_burstcount=>pDdrBurstCount,
            ddr_read=>pDdrRead, ddr_write=>pDdrWrite, ddr_busy=>pDdrBusy,
            ddr_readdatavalid=>pDdrReadValid, ddr_readdata=>pDdrReadData
        );
        cyc<=stb;
        nmia<='0';
        monpc<=(others=>'0');
    end generate;

	cpu_dbus<=	
		x"00" & INTM_ODAT				when INTM_OE='1' and tgca='1' else
		x"00" & INTS_ODAT				when INTS_OE='1' and tgca='1' else
		dbus;
	
	-- BEGIN PC98 DATA BUS
	-- Bit 8 marks a driven lane. Resolve devices before DMA byte routing so
	-- neither final byte feeds back into the other byte's priority mux.
	dbus_high<=
		'1' & LDR_WDAT				when LDR_OE='1' else
		'1' & cpuod(15 downto 8)		when cpuoe='1' and cpusel(1)='1' and DMAen='0' else
		'1' & DMA_ODAT				when DMA_DOE='1' else
		'1' & GCG_ODAT(15 downto 8)	when GCG_DOE='1' else
		'1' & DBIO_ODAT(15 downto 8)	when DBIO_DOE='1' else
		'1' & CB_RDAT0(15 downto 8)	when CB_RD1='1' and bussel(1)='1' else
		'1' & tramdo(15 downto 8)		when tramdoe(1)='1' else
		'1' & BNK89_ODAT				when BNK89_DOE='1' else
		'1' & BNKAB_ODAT				when BNKAB_DOE='1' else
		'1' & KBod					when KBoe='1' else
		'1' & SYSP_RDAT				when SYSP_DOE='1' else
		'1' & PTC_ODAT				when PTC_DOE='1' else
		'1' & MOUS_ODAT				when MOUS_DOE='1' else
		'1' & IO439_ODAT				when IO439_DOE='1' else
		'1' & x"04"					when ioaddr_odd=x"043b" and iord='1' else
		'1' & KNJ0_ODAT				when KNJ0_DOE='1' else
		'1' & KNJ1_ODAT				when KNJ1_DOE='1' else
		'1' & KNJ2_ODAT				when KNJ2_DOE='1' else
		'1' & IDE_ODAT(15 downto 8)	when IDE_DOE='1' else
		'1' & TSTMP_ODAT(15 downto 8)	when TSTMP_DOE='1' else
		'0' & x"ff";

	dbus_low<=
		'1' & LDR_WDAT				when LDR_OE='1' else
		'1' & cpuod(7 downto 0)		when cpuoe='1' and cpusel(0)='1' and DMAen='0' else
		'1' & INTM_ODAT				when INTM_OE='1' and tgca='0' else
		'1' & INTS_ODAT				when INTS_OE='1' and tgca='0' else
		'1' & GCG_ODAT(7 downto 0)	when GCG_DOE='1' else
		'1' & DBIO_ODAT(7 downto 0)	when DBIO_DOE='1' else
		'1' & CB_RDAT0(7 downto 0)	when CB_RD1='1' and bussel(0)='1' else
		'1' & tramdo(7 downto 0)		when tramdoe(0)='1' else
		'1' & aramdo(7 downto 0)		when aramdoe(0)='1' else
		'1' & NVR_ODAT				when NVR_DOE='1' else
		'1' & prnod					when prnoe='1' else
		'1' & COM_ODAT				when COM_DOE='1' else
		'1' & tGDCod					when tGDCoe='1' else
		'1' & gGDCod					when gGDCoe='1' else
		'1' & GPAL_ODAT				when GPAL_DOE='1' else
		'1' & IN00f0_ODAT				when IN00f0_DOE='1' else
		'1' & FDC_ODAT				when FDC_DOE='1' else
		'1' & FDCNT_ODAT				when FDCNT_DOE='1' else
		'1' & FDCIFS_ODAT				when FDCIFS_DOE='1' else
		'1' & FDIBM_ODAT				when FDIBM_DOE='1' else
		'1' & OPN_ODAT				when OPN_DOE='1' else
		'1' & SNDID_ODAT				when SNDID_OE='1' else
		'1' & pMPUReadData			when pMPUOE='1' else
		'1' & IDE_ODAT(7 downto 0)	when IDE_DOE='1' else
		'1' & TSTMP_ODAT(7 downto 0)	when TSTMP_DOE='1' else
		'0' & x"ff";

	dbus(15 downto 8)<=dbus_high(7 downto 0) when dbus_high(8)='1' or DMA_L2H='0' else dbus_low(7 downto 0);
	dbus(7 downto 0)<=dbus_low(7 downto 0) when dbus_low(8)='1' or DMA_H2L='0' else dbus_high(7 downto 0);
	-- CPU I/O writes never need peripheral read data. A selected lane already
	-- has CPU priority in the shared bus; preserve loader override separately.
	io_wdata <= LDR_WDAT & LDR_WDAT when LDR_OE='1' else cpuod;
	-- Only the FDC uses DMA channels 2/3; channels 0/1 have no request source.
	-- A memory write therefore comes from the loader, CPU, or FDC byte.
	-- The CPU GRCG produces a set/preserve pair; SDRAMC merges fresh read data.
	mem_wdata <= LDR_WDAT & LDR_WDAT when LDR_OE='1' else
		cpuod when DMAen='0' else
		FDC_ODAT & FDC_ODAT when FDC_DOE='1' else x"ffff";
	-- Memory-to-FDC DMA must retain memory-device priority and odd-byte routing,
	-- without pulling unrelated I/O read outputs into a floppy write register.
	dma_mem_high <=
		'1' & GCG_ODAT(15 downto 8) when GCG_DOE='1' else
		'1' & DBIO_ODAT(15 downto 8) when DBIO_DOE='1' else
		'1' & CB_RDAT0(15 downto 8) when CB_RD1='1' and bussel(1)='1' else
		'1' & tramdo(15 downto 8) when tramdoe(1)='1' else
		'0' & x"ff";
	dma_mem_low <=
		'1' & GCG_ODAT(7 downto 0) when GCG_DOE='1' else
		'1' & DBIO_ODAT(7 downto 0) when DBIO_DOE='1' else
		'1' & CB_RDAT0(7 downto 0) when CB_RD1='1' and bussel(0)='1' else
		'1' & tramdo(7 downto 0) when tramdoe(0)='1' else
		'1' & aramdo(7 downto 0) when aramdoe(0)='1' else
		'1' & NVR_ODAT when NVR_DOE='1' else
		'0' & x"ff";
	fdc_wdata <= LDR_WDAT when LDR_OE='1' else
		io_wdata(7 downto 0) when DMAen='0' else
		dma_mem_low(7 downto 0) when dma_mem_low(8)='1' or DMA_H2L='0' else
		dma_mem_high(7 downto 0);
	-- END PC98 DATA BUS
		
	CB_WR1<=
		LDR_WR	when LDR_OE='1' else
		GCG_WR1	when GCG_MCS='1' else
		MWR		when MSD_CS='1' else
		'0';
	
	CB_WR4<=	GCG_WR4 when GCG_MCS='1' else
				'0';
	
	CB_RD1<=	GCG_RD1	when GCG_MCS='1' else
				MRD		when MSD_CS='1' else
				'0';
	
	CB_RD4<=	GCG_RD4 when GCG_MCS='1' else
				'0';
	
	CB_RMW1<=	GCG_RMW1 when GCG_MCS='1' else
				'0';
	
	CB_RMW4<=	GCG_RMW4 when GCG_MCS='1' else
				'0';

	CB_BSEL<=
		"01"	when LDR_OE='1' and LDR_ADDR(0)='0' else
		"10"	when LDR_OE='1' and LDR_ADDR(0)='1' else
		bussel;
		
    CB_PRESERVE <= GCG_WMASK when GCG_MCS='1' else x"0000";
	CB_WDAT0<=	GCG_WDAT0	when GCG_MCS='1' else
				mem_wdata;
	CB_WDAT1<=	GCG_WDAT1	when GCG_MCS='1' else
				(others=>'0');
	CB_WDAT2<=	GCG_WDAT2	when GCG_MCS='1' else
				(others=>'0');
	CB_WDAT3<=	GCG_WDAT3	when GCG_MCS='1' else
				(others=>'0');
				
	CB_PSEL<=	GCG_WPSEL	when GCG_MCS='1' else
				"0001";
	
	abus<=	cpuaddr when DMAen='0' else DMA_UADR & DMA_OADR(15 downto 1);
	
	
	iowaitn<=TSTMP_WAITn;
	
	IOa	:IOack port map(tga,stb,abus(15 downto 1),cpusel,cpuoe,DMAen,cpu_iord,cpu_iowr,iowaitn,iack,cpuclk,irstn);
	
	iord<=	cpu_iord when DMAen='0' else DMA_IORD;
	iowr<=	cpu_iowr when DMAen='0' else DMA_IOWR;
	
    -- Independent byte-lane addresses: an aligned word can select both the
    -- even/low and odd/high peripheral at once. FFFF selects no mapped device.
    ioaddr_even<=cpuaddr(15 downto 1) & '0' when cpusel(0)='1' and DMAen='0' else x"ffff";
    ioaddr_odd<=cpuaddr(15 downto 1) & '1' when cpusel(1)='1' and DMAen='0' else x"ffff";
	ioaddr<=(others=>'1') when DMAen='1' else
			cpuaddr(15 downto 1) & '0' when cpusel(0)='1' else
			cpuaddr(15 downto 1) & '1';
	

	CB_BANK<=	RAM_BIOS(23 downto 22)	when LDR_OE='1' else
				MBANK;

	
	CB_ADDR<=	RAM_BIOS(21 downto 0) + ("000" & LDR_ADDR(19 downto 1))	when LDR_OE='1' else
				MADDR;
	
	DMA_CS<='1' when ioaddr_odd(15 downto 5)=(x"00" & "000") and ioaddr_odd(0)='1' else '0';

	DMA_REQ(1 downto 0)<=(others=>'0');
	
	DMA_REQ(2)<=	'0' when FDC_DMAE='0' else
						FDC_DRQ when FDCIF_H_Dn='1' else
						'0';
	
	DMA_REQ(3)<=	'0' when FDC_DMAE='0' else
						FDC_DRQ when FDCIF_H_Dn='0' else
						'0';
	
	DMA	:DMA8237 port map(
		PCS		=>DMA_CS,
		PADDR	=>ioaddr(4 downto 1),
		PRD		=>iord,
		PWR		=>iowr,
		PRDATA	=>DMA_ODAT,
		PWDATA	=>io_wdata(15 downto 8),
		PDOE	=>DMA_DOE,
		INT		=>open,
		
		DREQ	=>DMA_REQ,
		DACK	=>DMA_ACK,
		BUSREQ	=>DMA_BREQ,
		BUSACK	=>DMA_BACK,
		DADDR	=>DMA_OADR,
		DAOE	=>DMA_AOE,
		MEMRD	=>DMA_MRD,
		MEMWR	=>DMA_MWR,
		IORD	=>DMA_IORD,
		IOWR	=>DMA_IOWR,
		IOWAIT	=>not iowaitn,
		IOACK	=>iack,
		MEMACK	=>MEMack,
		TC		=>DMA_TC,
		ACARRY	=>DMA_ACARRY,
		CURCH	=>DMA_CURCH,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	FDC_DACK<=	'0' when FDC_DMAE='0' else
					DMA_ACK(2) when FDCIF_H_Dn='1' else
					DMA_ACK(3);
	
	FDC_TC<=		DMA_TC(2) when FDCIF_H_Dn='1' else
					DMA_TC(3);
	
	DMA_H2L<=	'1' when DMA_OADR(0)='0' and DMA_MWR='1' else
				'1' when DMA_OADR(0)='1' and DMA_MRD='1' else
				'0';
	DMA_L2H<=	'1' when DMA_OADR(0)='1' and DMA_MWR='1' else
				'1' when DMA_OADR(0)='0' and DMA_MRD='1' else
				'0';
	
	DMAS	:DMASW port map(
		cpustb	=>stb,
		
		dmabreq	=>DMA_BREQ,
		
		dmaen	=>DMAen,
		
		clk		=>cpuclk,
		rstn	=>irstn
	);
	DMA_BACK<=DMAen;
	
	cpuack<=ack when DMAen='0' else '0';

    -- Cache only fixed RAM below 80000h. External DMA must invalidate it;
    -- CPU writes through either banked window can also alias that RAM without
    -- matching ao486's physical-address snoop. Hold invalidation until the
    -- entire write/bus ownership interval ends, not merely its first cycle.
    -- BEGIN PC98 CACHE INVALIDATION
    -- Decode the two CPU windows directly. Following CB_ADDR here also
    -- traversed the DMA mux and full SDRAM map into the CPU fetch pipeline.
    -- Bank values 00..07 (bit 0 is ignored) select fixed RAM below 80000h;
    -- higher bank values select upper RAM, peripherals or extended memory.
    -- Keep the loader exclusion and the entire DMA ownership interval.
    cache_invalidate <= '1' when DMAen='1' else
        '1' when cpuoe='1' and stb='1' and tga='0' and LDR_OE='0' and
          ((cpuaddr(19 downto 17)="100" and BNK89_SEL(7 downto 3)="00000") or
           (cpuaddr(19 downto 17)="101" and BNKAB_SEL(7 downto 3)="00000")) else '0';
    -- END PC98 CACHE INVALIDATION
	
	DMAU_CS<='1' when ioaddr_odd(15 downto 3)=(x"002" & "0") and ioaddr_odd(0)='1' else '0';
	DMAUM_CS<='1' when ioaddr_odd=x"0029" else '0';
	
	DMAU	:DMAUADDR port map(
		CS		=>DMAU_CS,
		ADDR	=>ioaddr(2 downto 1),
		CSMODE	=>DMAUM_CS,
		WR		=>iowr,
		WDATA	=>io_wdata(15 downto 8),
		
		CURCH	=>DMA_CURCH,
		CARRY	=>DMA_ACARRY,
		ADDRU	=>DMA_UADRw,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);
	DMA_UADR<=DMA_UADRw(3 downto 0);
	
	DMAsel<="01" when DMA_OADR(0)='0' else
			"10" when DMA_OADR(0)='1' else
			"00";
	
	bussel<=cpusel when DMAen='0' else DMAsel;

	MMAP	:memorymap generic map(22) port map(
		CPUADDR	=>cpuaddr,
		CPUSEL	=>bussel,
		CPUTGA	=>tga,
		CPUSTB	=>stb,
		CPUOE		=>cpuoe,
		DMAEN		=>DMAen,
		DMAADDR	=>DMA_UADR & DMA_OADR(15 downto 1),
		DMARD		=>DMA_MRD,
		DMAWR		=>DMA_MWR,
		
		BNK89SEL	=>BNK89_SEL,
		BNKABSEL	=>BNKAB_SEL,

		SDR_CS		=>MSD_CS,
		SDR_BANK	=>MBANK,
		SDR_ADDR	=>MADDR,

		GRAM_CS		=>GCG_MCS,
		
		TRAM_CS		=>tramcs,
		TRAM_ADDR	=>tramaddr,
		
		ARAM_CS		=>aramcs,
		ARAM_ADDR	=>aramaddr,
		
		DBIOS_CS	=>DBIO_CS,
		DBIOS_ADDR	=>DBIO_ADDR,
	
		NVRAM_CS	=>NVR_CS,
		NVRAM_ADDR	=>NVR_ADDR,
	
		ITFEN		=>ITFen,
		BIOSEN		=>not BIOSRAM,
		SOUNDEN		=>SNDBIOSEN,
		VSEL		=>gGDC_CGRAMSEL,
		
		EMSEN		=>'1',
		NECEMSEN	=>NECEMSSEL,
		EMSA0		=>(others=>'0'),
		EMSA1		=>(others=>'0'),
		EMSA2		=>(others=>'0'),
		EMSA3		=>(others=>'0'),
		
		MRD			=>MRD,
		MWR			=>MWR,
		
		clk			=>cpuclk,
		rstn		=>irstn
	);
	MEMack<=CB_ACK or tramack or aramack or NVR_ACK;
	ack<=MEMack or iack;
	
--	DBIO	:diskbios port map(
--		address		=>DBIO_ADDR,
--		clock		=>cpuclk,
--		q			=>DBIO_ODAT
--	);
DBIO_ODAT<=(others=>'1');

	DBIO_DOE<=	MRD when DBIO_CS='1' else '0';
	
	GCG_IOCS<=	'1' when ioaddr_even(15 downto 2)=(x"007" & "11") and ioaddr_even(0)='0' else '0';
	gcg	:grcg generic map(true) port map(
		iocs		=>GCG_IOCS,
		ioaddr		=>ioaddr(1),
		iowr		=>iowr,
		iowdat		=>io_wdata(7 downto 0),
		
		pmemcs		=>GCG_MCS,
		ppsel		=>abus(2 downto 1),
		prd			=>MRD,
		pwr			=>MWR,
		prddat		=>GCG_ODAT,
		pwrdat		=>mem_wdata,
		poe			=>GCG_DOE,
		
		memrd1		=>GCG_RD1,
		memrd4		=>GCG_RD4,
		memwr1		=>GCG_WR1,
		memwr4		=>GCG_WR4,
		memrmw1		=>GCG_RMW1,
		memrmw4		=>GCG_RMW4,
		memrdat0	=>CB_RDAT0,
		memrdat1	=>CB_RDAT1,
		memrdat2	=>CB_RDAT2,
		memrdat3	=>CB_RDAT3,
        memwmask=>GCG_WMASK,
		memwdat0	=>GCG_WDAT0,
		memwdat1	=>GCG_WDAT1,
		memwdat2	=>GCG_WDAT2,
		memwdat3	=>GCG_WDAT3,
		memwrpsel	=>GCG_WPSEL,
		
		clk			=>cpuclk,
		rstn		=>srstn
	);	
	
	IN00f0_ODAT<="11101011";
	IN00f0_DOE<='1' when ioaddr_even=x"00f0" and iord='1' else '0';
	
	IO043F_CS<='1' when ioaddr_odd=x"043f" else '0';
	
	IO43F	:IO043F port map(
		CS		=>IO043F_CS,
		WR		=>iowr,
		WDAT	=>io_wdata(15 downto 8),
		
		NECEMSSEL	=>NECEMSSEL,
		BNK89SEL	=>open,
		SASIRAMEN	=>open,
		SCSIRAMEN	=>open,
		CACHEFLASH	=>open,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);

	IO053D	:IO_RW generic map(x"053d",x"00") port map(
		ADR		=>ioaddr_odd,
		RD		=>iord,
		WR		=>iowr,
		DATIN	=>io_wdata(15 downto 8),
		DATOUT	=>open,
		DATOE	=>open,
		
		bit7	=>SNDBIOSEN,
		bit6	=>SASIBIOSEN,
		bit5	=>SCSIBIOSEN,
		bit4	=>IDEBIOSEN,
		bit3	=>open,
		bit2	=>open,
		bit1	=>BIOSRAM,
		bit0	=>open,

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	
	RWIN8	:IO_RW generic map(x"0461",x"08") port map(
		ADR		=>ioaddr_odd,
		RD		=>iord,
		WR		=>iowr,
		DATIN	=>io_wdata(15 downto 8),
		DATOUT	=>BNK89_ODAT,
		DATOE	=>BNK89_DOE,
		
		bit7	=>BNK89_SEL(7),
		bit6	=>BNK89_SEL(6),
		bit5	=>BNK89_SEL(5),
		bit4	=>BNK89_SEL(4),
		bit3	=>BNK89_SEL(3),
		bit2	=>BNK89_SEL(2),
		bit1	=>BNK89_SEL(1),
		bit0	=>BNK89_SEL(0),

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	RWINA	:IO_RW generic map(x"0463",x"0a") port map(
		ADR		=>ioaddr_odd,
		RD		=>iord,
		WR		=>iowr,
		DATIN	=>io_wdata(15 downto 8),
		DATOUT	=>BNKAB_ODAT,
		DATOE	=>BNKAB_DOE,
		
		bit7	=>BNKAB_SEL(7),
		bit6	=>BNKAB_SEL(6),
		bit5	=>BNKAB_SEL(5),
		bit4	=>BNKAB_SEL(4),
		bit3	=>BNKAB_SEL(3),
		bit2	=>BNKAB_SEL(2),
		bit1	=>BNKAB_SEL(1),
		bit0	=>BNKAB_SEL(0),

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	INTM_CS<='1' when ioaddr_even(15 downto 2)="00000000000000" and ioaddr_even(0)='0' else '0';
	-- MPU deasserts its level request when software polls the last byte.
	-- Other legacy producers include one-clock pulses and keep their latch.
	INT_M	:z8259 generic map(RETRACTABLE_IRQS => x"40") port map(
		CS		=>INTM_CS,
		ADDR	=>ioaddr(1),
		DIN		=>io_wdata(7 downto 0),
		DOUT	=>INTM_ODAT,
		DOE		=>INTM_OE,
		RD		=>iord,
		WR		=>iowr,
		
		IR0		=>PTC_CNTOUT(0),
		IR1		=>KBINT,
		IR2		=>VRTC,
		IR3		=>'0',
		IR4		=>not COM_INTn,
		IR5		=>'0',
		IR6		=>pMPUIRQ,
		IR7		=>INTS,
		
		INT		=>INTM,
		INTA	=>tgca,
		
		CASI	=>(others=>'0'),
		CASO	=>INTCAS,
		CASM	=>'1',
		
		clk		=>cpuclk,
		rstn	=>rstn
	);
	
	FDC_INTS<=(not FDC_INTn) or (VFO_INT and VFO_INTEN);
	
	IR10<= FDC_INTS when FDCIF_H_Dn='0' else '0';
	IR11<= FDC_INTS when FDCIF_H_Dn='1' else '0';
	IR12<= (not OPN_INTn) or PCM_IRQ;
	IR13<=MOUS_INTp and MOUS_INTe;
	
	INTS_CS<='1' when ioaddr_even(15 downto 2)="00000000000010" and ioaddr_even(0)='0' else '0';
	INT_S	:z8259 port map(
		CS		=>INTS_CS,
		ADDR	=>ioaddr(1),
		DIN		=>io_wdata(7 downto 0),
		DOUT	=>INTS_ODAT,
		DOE		=>INTS_OE,
		RD		=>iord,
		WR		=>iowr,
		
		IR0		=>'0',
		IR1		=>IDE_INT,
		IR2		=>IR10,
		IR3		=>IR11,
		IR4		=>IR12,
		IR5		=>IR13,
		IR6		=>'0',
		IR7		=>'0',
		
		INT		=>INTS,
		INTA	=>tgca,
		
		CASI	=>INTCAS,
		CASO	=>open,
		CASM	=>'0',
		
		clk		=>cpuclk,
		rstn	=>rstn
	);

	VID	:CRTC98 port map(
		TRAM_ADR	=>vaddr,
		TRAM_DAT	=>vtdat,
		TRAM_ATR	=>vadat,
		
		KNJSEL		=>VID_KNJSEL,
		KNJADR		=>VID_KNJADDR,
		KNJDAT		=>VID_FNTDAT,

		ETRAM_ADR	=>open,
		ETRAM_DAT	=>(others=>'0'),
		ECURL			=>(others=>'0'),
		ECURC			=>(others=>'0'),
		ECUREN		=>'0',
		
		GRAMADR		=>GADDR,
		GRAMRD		=>GRAMRD,
		GRAMACK		=>GRAMACK,
		GRAMDAT0	=>GRDAT0,
		GRAMDAT1	=>GRDAT1,
		GRAMDAT2	=>GRDAT2,
		GRAMDAT3	=>GRDAT3,
		
		ROUT		=>VidR4,
		GOUT		=>VidG4,
		BOUT		=>VidB4,
		
		HSYNC		=>pVideoHS,
		VSYNC		=>pVideoVS,
		VIDEOEN	=>pVideoEN,
		
		TBASEADDR	=>tGDC_BASEADDR(12 downto 0),
		HMODE		=>not tGDC_C40,
		VLINES		=>tGDC_CHARLINES,
		TPITCH		=>tGDC_PITCH,

		GRAPHEN		=>gGDC_GRAPHEN,
		DOTPLINE	=>gGDC_DOTPLINE,
		LOWBL		=>GLOWBLK,
		GCOLOR		=>'0',
		MONOSEL		=>(others=>'0'),
		TXTEN		=>tGDC_VIDEN,

		CURADDR		=>tGDC_CURADDR,
		CURE		=>tGDC_CUREN,
		CURUPPER	=>tGDC_iCURUPPER,
		CURLOWER	=>tGDC_iCURLOWER,
		CBLINK		=>not tGDC_CURBLINK,
		BLINKRATE	=>tGDC_BLRATE,

		GBASEADDR0	=>gGDC_BASEADDR0(13 downto 0),
		GBASEADDR1	=>gGDC_BASEADDR1(13 downto 0),
		GLINENUM0	=>gGDC_LINENUM0,
		GLINENUM1	=>gGDC_LINENUM1,
		GPITCH		=>gGDC_PITCH,

		EMUMODE		=>'0',

		VRTC		=>VRTC_video,
		HRTC		=>HRTC_video,

		GPALNO		=>GPAL_NO,
		GPALR		=>GPAL_R,
		GPALG		=>GPAL_G,
		GPALB		=>GPAL_B,

		gclk		=>grpclk,
		clk			=>vidclk,
		rstn		=>video_logic_rstn
	);
	
	-- Keep retrace decoding out of the CPU read mux and PIC priority path.
	retrace_status : entity work.video_retrace_cdc port map (
		video_clk => vidclk, video_rstn => video_logic_rstn,
		cpu_clk => cpuclk, cpu_rstn => srstn,
		vrtc_in => VRTC_video, hrtc_in => HRTC_video,
		vrtc_out => VRTC, hrtc_out => HRTC
	);
	pVideoClk<=grpclk;
	pVideoR<=VidR4 & VidR4;
	pVideoG<=VidG4 & VidG4;
	pVideoB<=VidB4 & VidB4;
--	monFntAdr<=VID_KNJADDR;
--	monFntDat<=VID_KNJ1DAT;
--	KNJ1	:KANJI1ROM PORT map(
--		address		=>VID_KNJADDR,
--		clock		=>vidclk,
--		q			=>VID_KNJ1DAT
--	);

	KRAMC	:KNJRAMCONT generic map(
		LDR_AWIDTH	=>20,
		LDR_BGNADDR	=>x"040000"
	)port map(
		LDR_ADDR		=>LDR_ADDR,
		LDR_EN		=>LDR_OE,
		LDR_WR		=>LDR_WR,
		LDR_WDAT		=>LDR_WDAT,
		
		ioaddr		=>ioaddr_odd,
		iowr		=>iowr,
		iord		=>iord,
		wrdat		=>io_wdata(15 downto 8),

		KNJRAMSEL	=>KNJ_RAMSEL,
		KNJRAMADDR	=>KNJ_ADDR,
		KNJRAMWDAT	=>KNJ_WRDAT,
		KNJRAMWR	=>KNJ_WR,
		KNJRAMOE	=>KNJ_DOE,
		
		clk			=>cpuclk,
		rstn		=>irstn
	);
	KNJ0_WR<=KNJ_WR when KNJ_RAMSEL="00" else '0';
	KNJ1_WR<=KNJ_WR when KNJ_RAMSEL="01" else '0';
	KNJ2_WR<=KNJ_WR when KNJ_RAMSEL="10" else '0';
	KNJ0_DOE<=	KNJ_DOE when KNJ_RAMSEL="00" else '0';
	KNJ1_DOE<=	KNJ_DOE when KNJ_RAMSEL="01" else '0';
	KNJ2_DOE<=	KNJ_DOE when KNJ_RAMSEL="10" else '0';
	

	-- Text, attributes and font fetches use the renderer pixel clock.
	-- CPU writes stay on the independent CPU ports of these dual-port RAMs.
	KNJ0	:KANJI1RAMDP port map(
		address_a		=>VID_KNJADDR,
		address_b		=>KNJ_ADDR,
		clock_a		=>grpclk,
		clock_b		=>cpuclk,
		data_a		=>(others=>'0'),
		data_b		=>KNJ_WRDAT,
		wren_a		=>'0',
		wren_b		=>KNJ0_WR,
		q_a			=>VID_KNJ0DAT,
		q_b			=>KNJ0_ODAT
	);
	
	KNJ1	:KANJI1RAMDP port map(
		address_a		=>VID_KNJADDR,
		address_b		=>KNJ_ADDR,
		clock_a		=>grpclk,
		clock_b		=>cpuclk,
		data_a		=>(others=>'0'),
		data_b		=>KNJ_WRDAT,
		wren_a		=>'0',
		wren_b		=>KNJ1_WR,
		q_a			=>VID_KNJ1DAT,
		q_b			=>KNJ1_ODAT
	);
	
	KNJ2	:GAIJIRAMDP port map(
		address_a		=>VID_KNJADDR,
		address_b		=>KNJ_ADDR,
		clock_a		=>grpclk,
		clock_b		=>cpuclk,
		data_a		=>(others=>'0'),
		data_b		=>KNJ_WRDAT,
		wren_a		=>'0',
		wren_b		=>KNJ2_WR,
		q_a			=>VID_KNJ2DAT,
		q_b			=>KNJ2_ODAT
	);
	
	VID_FNTDAT<=	VID_KNJ0DAT when VID_KNJSEL="00" else
					VID_KNJ1DAT when VID_KNJSEL="01" else
					VID_KNJ2DAT when VID_KNJSEL="10" else
					(others=>'0');
	
	GRAMADR<=	RAM_VRAMF(21 downto 16) & GADDR & "00" when gGDC_VGRAMSEL='0' else
					RAM_VRAMB(21 downto 16) & GADDR & "00";
	
	tmem	:tvram port map(tramcs,tramaddr,bussel,MRD,MWR,mem_wdata,tramdo,tramdoe,tramack,cpuclk,vaddr(11 downto 0),vtdat,grpclk,srstn);
	amem	:tvram port map(aramcs,aramaddr,'0' & bussel(0),MRD,MWR,x"00" & mem_wdata(7 downto 0),aramdo,aramdoe,aramack,cpuclk,vaddr(11 downto 0),vadatw,grpclk,srstn);
	vadat<=vadatw(7 downto 0);

	
	prncsn<='0' when ioaddr_even(15 downto 3)="0000000001000" and ioaddr_even(0)='0' else '1';
	dat42<="100" & pDip1 & "100";
	prnppi	:ppi8255 port map(prncsn,not iord,not iowr,ioaddr(2 downto 1),io_wdata(7 downto 0),prnod,prnoe,(others=>'0'),open,open,dat42,open,open,(others=>'0'),open,open,(others=>'0'),open,open,cpuclk,srstn);
	
	tGDCcs<='1' when ioaddr_even(15 downto 4)="000000000110" and ioaddr_even(0)='0' else '0';

	textgdc	:TXTGDC port map(
		CS		=>tGDCcs,
		ADDR	=>ioaddr(3 downto 1),
		RD		=>iord,
		WR		=>iowr,
		DIN		=>io_wdata(7 downto 0),
		DOUT	=>tGDCod,
		DOE		=>tGDCoe,
		
		LPEND	=>'0',
		VRTC	=>VRTC,
		HRTC	=>HRTC,
		
		ATRSEL	=>open,
		C40		=>tGDC_C40,
		GRMONO	=>open,
		FONTSEL	=>open,
		GRPMODE	=>GLOWBLK,
		KACMODE	=>open,
		NVMWPROT=>NVR_WPROT,
		DISPEN	=>open,
		COLORMODE=>tGDC_COLORMODE,
		EGCEN	=>open,
		GDCCLK	=>open,
		GDCCLK2	=>open,
		CUREN	=>tGDC_CUREN,
		CHARLINES=>tGDC_CHARLINES,
		BLRATE	=>tGDC_BLRATE,
		CURBLINK=>tGDC_CURBLINK,
		CURUPPER=>tGDC_CURUPPER,
		CURLOWER	=>tGDC_CURLOWER,
		VIDEN		=>tGDC_VIDEN,
		SAD0		=>tGDC_BASEADDR,
		SAD1		=>open,
		SAD2		=>open,
		SAD3		=>open,
		SL0			=>open,
		SL1			=>open,
		SL2			=>open,
		SL3			=>open,
		PITCH		=>tGDC_PITCH,
		EAD			=>tGDC_CURADDR,

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	tGDC_iCURUPPER<=conv_integer(tGDC_CURUPPER);
	tGDC_iCURLOWER<=conv_integer(tGDC_CURLOWER);
	
	gGDCcs<='1' when ioaddr_even(15 downto 3)="0000000010100" and ioaddr_even(0)='0' else '0';
	graphgdc	:GRAGDC port map(
		CS		=>gGDCcs,
		ADDR	=>ioaddr(2 downto 1),
		RD		=>iord,
		WR		=>iowr,
		DIN		=>io_wdata(7 downto 0),
		DOUT	=>gGDCod,
		DOE		=>gGDCoe,
		
		LPEND	=>'1',
		VRTC	=>VRTC,
		HRTC	=>HRTC,
		
		VRAMSEL	=>gGDC_VGRAMSEL,
		CRAMSEL	=>gGDC_CGRAMSEL,
		
		GRAPHEN		=>gGDC_GRAPHEN,
		VZOOM		=>open,
		BASEADDR0	=>gGDC_BASEADDR0,
		BASEADDR1	=>gGDC_BASEADDR1,
		SL0			=>gGDC_LINENUM0,
		SL1			=>gGDC_LINENUM1,
		IM			=>open,
		PITCH		=>gGDC_PITCH,
		DOTPLINE	=>gGDC_DOTPLINE,

		GDC_ADDR	=>GDC_ADDR,
		GDC_RDAT	=>GDC_RDAT,
		GDC_WDAT	=>GDC_WDAT,
		GDC_RD		=>GDC_RD,
		GDC_WR		=>GDC_WR,
		GDC_MACK	=>GDC_RAMACK,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	GDCMMAP	:GDC_MMAP generic map(22) port map(
		GDC_ADDR	=>GDC_ADDR,
		
		GRAMSEL		=>gGDC_CGRAMSEL,
		
		RAMBANK		=>GDC_RAMBANK,
		RAMADDR		=>GDC_RAMADDR
	);

	gcggdc	:grcg generic map(SPLIT_RMW=>true) port map(
		iocs		=>GCG_IOCS,
		ioaddr		=>ioaddr(1),
		iowr		=>iowr,
		iowdat		=>io_wdata(7 downto 0),
		
		pmemcs		=>'1',
		ppsel		=>GDC_RAMADDR(1 downto 0),
		prd			=>GDC_RD,
		pwr			=>GDC_WR,
		prddat		=>GDC_RDAT,
		pwrdat		=>GDC_WDAT,
		poe			=>open,
		
		memrd1		=>GCG_GDC_RD1,
		memrd4		=>GCG_GDC_RD4,
		memwr1		=>GCG_GDC_WR1,
		memwr4		=>GCG_GDC_WR4,
		memrmw1		=>GCG_GDC_RMW1,
		memrmw4		=>GCG_GDC_RMW4,
		memrdat0		=>GCG_GDC_RDAT0,
		memrdat1		=>GCG_GDC_RDAT1,
		memrdat2		=>GCG_GDC_RDAT2,
		memrdat3		=>GCG_GDC_RDAT3,
        memwmask=>GCG_GDC_WMASK,
		memwdat0		=>GCG_GDC_WDAT0,
		memwdat1		=>GCG_GDC_WDAT1,
		memwdat2		=>GCG_GDC_WDAT2,
		memwdat3		=>GCG_GDC_WDAT3,
		memwrpsel	=>GCG_GDC_WPSEL,
		
		clk			=>cpuclk,
		rstn		=>srstn
	);	

	GPAL_CS<='1' when ioaddr_even(15 downto 3)="0000000010101" and ioaddr_even(0)='0' else '0';
	pal	:grpal generic map(VIDEO_STAGED=>true) port map(
		CS			=>GPAL_CS,
		ADDR		=>ioaddr(2 downto 1),
		WR			=>iowr,
		RD			=>iord,
		WRDAT		=>io_wdata(7 downto 0),
		RDDAT		=>GPAL_ODAT,
		DOE			=>GPAL_DOE,
		
		COLORMODE	=>tGDC_COLORMODE,
		NUMIN		=>GPAL_NO,
		vidR		=>GPAL_R,
		vidG		=>GPAL_G,
		vidB		=>GPAL_B,
		
		clk			=>cpuclk,
		rstn		=>srstn,
        video_clk=>vidclk
	);
	
	ITFswcs<='1' when ioaddr_odd=x"043d" else '0';
	ITFs	:ITFSW port map(ITFswcs,iowr,io_wdata(15 downto 8),ITFen,cpuclk,srstn);
	
	nv	:nvram98 port map(
		addr		=>NVR_ADDR,
		cs			=>NVR_CS,
		wrdat		=>mem_wdata(7 downto 0),
		wr			=>MWR,
		rd			=>MRD,
		wprot		=>NVR_WPROT,
		rddat		=>NVR_ODAT,
		ack		=>NVR_ACK,
		
		clk		=>cpuclk,
		mrstn		=>vrstn,
		rstn		=>srstn
	);
	NVR_DOE<=NVR_CS and MRD;
	
	
	process(cpuclk,vrstn)begin
		if(vrstn='0')then
			KBCLKIN<='1';
			KBDATIN<='1';
		elsif(cpuclk' event and cpuclk='1')then
			KBCLKIN<=pPs2Clkin;
			KBDATIN<=pPs2Datin;
		end if;
	end process;

	pPs2Clkout<=KBCLKOUT;
	pPs2Datout<=KBDATOUT;

	KBCS<='1' when ioaddr_odd(15 downto 2)="00000000010000" and ioaddr_odd(0)='1' else '0';

	KB		:KBCONV generic map(SYSFREQ,400,0) port map(
		CS		=>KBCS,
		ADDR	=>ioaddr(1),
		RD		=>iord,
		WR		=>iowr,
		RDAT	=>KBod,
		WDAT	=>io_wdata(15 downto 8),
		OE		=>KBoe,
		INT		=>KBINT,

		KBCLKIN	=>KBCLKIN,
		KBCLKOUT=>KBCLKOUT,
		KBDATIN	=>KBDATIN,
		KBDATOUT=>KBDATOUT,

		emuen		=>EMUEN,
		emurx		=>EMU_KBRX,
		emurxdat	=>EMU_KBRXDAT,
		
		monout	=>open,
		
		clk		=>cpuclk,
		rstn		=>srstn
	);
	
	SYSP_CS<='1' when ioaddr_odd(15 downto 3)=(x"003" & '0') and ioaddr_odd(0)='1' else '0';
	
	SYSP	:e8255 generic map('1') port map(
		CSn		=>not SYSP_CS,
		RDn		=>not iord,
		WRn		=>not iowr,
		ADR		=>ioaddr(2 downto 1),
		DATIN	=>io_wdata(15 downto 8),
		DATOUT	=>SYSP_RDAT,
		DATOE	=>SYSP_DOE,
		
		PAi		=>SYSP_PAI,
		PAo		=>SYSP_PAO,
		PAoe	=>open,
		PBi		=>SYSP_PBI,
		PBo		=>SYSP_PBO,
		PBoe	=>open,
		PCHi	=>SYSP_PCI(7 downto 4),
		PCHo	=>SYSP_PCO(7 downto 4),
		PCHoe	=>open,
		PCLi	=>SYSP_PCI(3 downto 0),
		PCLo	=>SYSP_PCO(3 downto 0),
		PCLoe	=>open,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	SYSP_PAI<=pDip2;
	SYSP_PBI<="0000100" & RTC_CDAT;
	SYSP_PCI<=SYSP_PCO;
	BEEPON<=not SYSP_PCO(3);
	
	WR20	:IO_WR generic map(x"0020") port map(
		ADR		=>ioaddr_even,
		WR		=>iowr,
		DAT		=>io_wdata(7 downto 0),
		
		bit7	=>open,
		bit6	=>open,
		bit5	=>RTC_CDI,
		bit4	=>RTC_CCK,
		bit3	=>RTC_CSTB,
		bit2	=>RTC_C(2),
		bit1	=>RTC_C(1),
		bit0	=>RTC_C(0),

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	U_RTC	:rtc4990MiSTer generic map(SYSFREQ*1000,x"00") port map(
		DCLK	=>RTC_CCK,
		DIN	=>RTC_CDI,
		DOUT	=>RTC_CDAT,
		C		=>RTC_C,
		CS		=>'1',
		STB		=>not RTC_CSTB,
		OE		=>'1',

		RTCIN	=>sysrtc,
		
		sclk	=>cpuclk,
		rstn	=>srstn
	);

	O439	:IO_WR generic map(x"0439") port map(
		ADR		=>ioaddr_odd,
		WR		=>iowr,
		DAT		=>io_wdata(15 downto 8),
		
		bit7	=>open,
		bit6	=>open,
		bit5	=>open,
		bit4	=>open,
		bit3	=>open,
		bit2	=>DMA1MMASK,
		bit1	=>FASTLIOBIOSEN,
		bit0	=>open,

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	I439	:IO_RD generic map(x"0439") port map(
		ADR		=>ioaddr_odd,
		RD		=>iord,
		DATOUT	=>IO439_ODAT,
		DATOE	=>IO439_DOE,
		
		bit7	=>'0',
		bit6	=>'0',
		bit5	=>'0',
		bit4	=>'0',
		bit3	=>'1',
		bit2	=>DMA1MMASK,
		bit1	=>FASTLIOBIOSEN,
		bit0	=>'0',

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	FDCH_CS<=	'1' when (ioaddr_even(15 downto 2)="00000000100100" and ioaddr_even(0)='0')else '0';
	FDCD_CS<=	'1' when (ioaddr_even(15 downto 2)="00000000110010" and ioaddr_even(0)='0')else '0';
	FDC_CSn<=	not FDCH_CS when FDCIF_H_Dn='1' else
					not FDCD_CS;
--	FDC_CSn<=not(FDCH_CS or FDCD_CS);
			
	FDT	:FDtiming generic map(SYSFREQ) port map(
		drv0sel		=>'0',
		drv1sel		=>'0',
		drv0sele	=>'0',
		drv1sele	=>'0',
	
		drv0hd		=>FDC_H_Dn,
		drv0hdi		=>'1',		--IBM 1.44MB format
		drv1hd		=>FDC_H_Dn,
		drv1hdi		=>'1',		--IBM 1.44MB format
		
		drv0hds		=>open,
		drv1hds		=>open,
		
		drv0int		=>FDC_int,
		drv1int		=>open,
		
		hmssft		=>FDC_hmssft,
		
		clk			=>cpuclk,
		rstn		=>srstn and (not FDC_RESET)
	);

	FD	:FDC generic map(
		maxtrack	=>85,
		maxbwidth	=>(BR_300_D*SYSFREQ/1000000),
		rdytout		=>800,
		preseek		=>'0',
		sysclk		=>SYSFREQ/1000
	)
	port map(
		RDn		=>not iord,
		WRn		=>not iowr,
		CSn		=>FDC_CSn,
		A0			=>ioaddr(1),
		WDAT		=>fdc_wdata,
		RDAT		=>FDC_ODAT,
		DATOE		=>FDC_DOE,
		DACKn		=>not FDC_DACK,
		DRQ		=>FDC_DRQ,
		TC			=>FDC_TC,
		INTn		=>FDC_INTn,
		WAITIN	=>FDC_WAIT,

		WREN	=>FDE_WRENn,
		WRBIT	=>FDE_WRBITn,
		RDBIT	=>FDE_RDBITn,
		STEP	=>FDE_STEPn,
		SDIR	=>FDE_SDIRn,
		WPRT	=>FDE_WPROTn,
		track0	=>FDE_TRACK0n,
		index	=>FDE_INDEXn,
		side	=>FDE_SIDEn,
		usel	=>FDC_USEL,
		READY	=>FDE_READYn and (FDC_FREADY),
		
		int0	=>FDC_int,
		int1	=>FDC_int,
		int2	=>FDC_int,
		int3	=>FDC_int,
		
		td0		=>'1',
		td1		=>'1',
		td2		=>'1',
		td3		=>'1',
		
		hmssft	=>FDC_hmssft,
		
		busy	=>FDC_BUSY,
		mfm	=>FDE_MFM,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);

	
	FDCNT_CS<=	'1' when (ioaddr_even=x"0094" and FDCIF_H_Dn='1') else
					'1' when (ioaddr_even=x"00cc" and FDCIF_H_Dn='0') else
					'0';
	
	FDC_USELbn<=	"1110" when FDC_USEL="00" else
						"1101" when FDC_USEL="01" else
						"1011" when FDC_USEL="10" else
						"1000" when FDC_USEL="11" else
						"1111";
    -- Register activity in its source domain before the overlay synchronizer.
    process(cpuclk,irstn) begin
        if irstn='0' then pFloppyAccess<="00";
        elsif rising_edge(cpuclk) then
            if FDC_BUSY='1' and FDC_USEL="00" then pFloppyAccess<="01";
            elsif FDC_BUSY='1' and FDC_USEL="01" then pFloppyAccess<="10";
            else pFloppyAccess<="00";
            end if;
        end if;
    end process;
	
	DISKE	:component diskemu_mister 	generic map(SYSFREQ,SYSFREQ,10) port map(
	--SASI
		sasi_din		=>(others=>'0'),
		sasi_dout	=>open,
		sasi_sel		=>'0',
		sasi_bsy		=>open,
		sasi_req		=>open,
		sasi_ack		=>'0',
		sasi_io		=>open,
		sasi_cd		=>open,
		sasi_msg		=>open,
		sasi_rst		=>'0',

		--FDD
		fdc_useln	=>FDC_USELbn(1 downto 0),
		fdc_motorn	=>not FDC_MOTOR & not FDC_MOTOR,
		fdc_readyn	=>FDE_READYn,
		fdc_wrenn	=>FDE_WRENn,
		fdc_wrbitn	=>FDE_WRBITn,
		fdc_rdbitn	=>FDE_RDBITn,
		fdc_stepn	=>FDE_STEPn,
		fdc_sdirn	=>FDE_SDIRn,
		fdc_track0n	=>FDE_TRACK0n,
		fdc_indexn	=>FDE_INDEXn,
		fdc_siden	=>FDE_SIDEn,
		fdc_wprotn	=>FDE_WPROTn,
		fdc_eject	=>pFDEJECT,
		fdc_indisk	=>open,
		fdc_trackwid=>'1',
		fdc_dencity	=>FDC_H_Dn,
		fdc_rpm		=>'0',
		fdc_mfm		=>FDE_MFM,
		
	--FD emulator
		fde_tracklen=>open,
		fde_ramaddr	=>FDE_RAMADDR,
		fde_ramrdat	=>FDE_RAMRDAT,
		fde_ramwdat	=>FDE_RAMWDAT,
		fde_ramwr	=>FDE_RAMWR,
		fde_ramwait	=>FDE_RAMWAIT,
		fec_ramaddrh =>FEC_RAMADDRH,
		fec_ramaddrl =>FEC_RAMADDRL,
		fec_ramwe	=>FEC_RAMWE,
		fec_ramrdat	=>FEC_RAMWDAT,
		fec_ramwdat	=>FEC_RAMRDAT,
		fec_ramrd	=>FEC_RAMRD,
		fec_ramwr	=>FEC_RAMWR,
		fec_rambusy	=>FEC_RAMBUSY,
		
		fec_fdsync	=>pFDSYNC,

	--SRAM
		sram_cs		=>'0',
		sram_addr	=>(others=>'0'),
		sram_rdat	=>open,
		sram_wdat	=>(others=>'0'),
		sram_rd		=>'0',
		sram_wr		=>"00",
		sram_wp		=>'1',
		
		sram_ld		=>psramld,
		sram_st		=>psramst,

	--MiSTer
		mist_mounted	=>mist_mounted,
		mist_readonly	=>mist_readonly,
		mist_imgsize	=>mist_imgsize,

		mist_lba			=>mist_lba,
		mist_rd			=>mist_rd,
		mist_wr			=>mist_wr,
		mist_ack			=>mist_ack,

		mist_buffaddr	=>mist_buffaddr,
		mist_buffdout	=>mist_buffdout,
		mist_buffdin	=>mist_buffdin,
		mist_buffwr		=>mist_buffwr,
		
	--common
		initdone		=>EMU_INIDONE,
		busy			=>pLED,
		fclk			=>cpuclk,
		sclk			=>cpuclk,
        -- FECcont address/write controls and both buffer users run on cpuclk.
        -- Its two-cycle registered read fits the existing FEC wait states.
		rclk			=>cpuclk,
		rstn			=>vrstn
	);

	FECC :FECcont generic map(23) port map(
		HIGHADDR	=>'0' & FEC_RAMADDRH,
		BUFADDR	=>FEC_RAMADDRL,
		RD			=>FEC_RAMRD,
		WR			=>FEC_RAMWR,
		RDDAT		=>FEC_RAMRDAT,
		WRDAT		=>FEC_RAMWDAT,
		BUFRD		=>open,
		BUFWR		=>FEC_RAMWE,
		BUFWAIT	=>'0',
		BUSY		=>FEC_RAMBUSY,
		
		SDR_ADDR	=>FEC_ADDR,
		SDR_RD	=>FEC_RD,
		SDR_WR	=>FEC_WR,
		SDR_RDAT	=>FEC_RDAT,
		SDR_WDAT	=>FEC_WDAT,
		SDR_WAIT	=>FEC_RAMWAIT,
		
		clk		=>cpuclk,
		rstn		=>irstn
	);
	
	FDCNT_RD	:IO_RDP port map(
		CS		=>FDCNT_CS,
		RD		=>iord,
		DATOUT=>FDCNT_ODAT,
		DATOE	=>FDCNT_DOE,
		
		bit7	=>'0',
		bit6	=>'1',
		bit5	=>'0',
		bit4	=>FDC_READY,
		bit3	=>'0',
		bit2	=>'1',
		bit1	=>'0',
		bit0	=>'0',

		clk	=>cpuclk,
		rstn	=>srstn
	);
	
	FDCNT_WR	:IO_WRP port map(
		CS		=>FDCNT_CS,
		WR		=>iowr,
		DAT	=>io_wdata(7 downto 0),
		
		bit7	=>FDC_RESET,
		bit6	=>FDC_FREADY,
		bit5	=>open,
--		bit4	=>FDC_DMAE,
		bit3	=>FDC_MOTOR,
		bit2	=>VFO_INTEN,
		bit1	=>open,
		bit0	=>VFO_TSTART,

		clk	=>cpuclk,
		rstn	=>srstn
	);
	FDC_DMAE<='1';
	
	fdcifsr	:IO_RD generic map(x"00be") port map(
		ADR	=>ioaddr_even,
		RD		=>iord,
		DATOUT=>FDCIFS_ODAT,
		DATOE	=>FDCIFS_DOE,
		
		bit7	=>'0',
		bit6	=>'0',
		bit5	=>'0',
		bit4	=>'0',
		bit3	=>'1',
		bit2	=>'0',
		bit1	=>FDC_H_Dn,
		bit0	=>FDCIF_H_Dn,

		clk	=>cpuclk,
		rstn	=>srstn
	);
	
	fdcifsw	:IO_WR generic map(x"00be") port map(
		ADR	=>ioaddr_even,
		WR		=>iowr,
		DAT	=>io_wdata(7 downto 0),
		
		bit7	=>open,
		bit6	=>open,
		bit5	=>open,
		bit4	=>open,
		bit3	=>open,
		bit2	=>open,
		bit1	=>FDC_H_Dn,
		bit0	=>FDCIF_H_Dn,

		clk	=>cpuclk,
		rstn	=>srstn
	);
	
	-- Preserve the original 100 ns interrupt pulse when changing SYSFREQ.
	VFOTIM	:fixtimer generic map(200,2*SYSFREQ/20000) port map(
		start	=>VFO_TSTART,
		sft	=>FDC_hmssft,
		
		pulse	=>VFO_INT,
		
		clk	=>cpuclk,
		rstn	=>srstn
	);
	
	FDIBM_CS<='1' when ioaddr_even=x"04be" else '0';
	FDIBM_DSn(0)<='0' when FDC_USEL="00" else '1';
	FDIBM_DSn(1)<='0' when FDC_USEL="01" else '1';
	
	IBM	:FDDIBM port map(
		CS	=>FDIBM_CS,
		RD	=>iord,
		WR	=>iowr,
		
		WRDAT	=>io_wdata(7 downto 0),
		RDDAT	=>FDIBM_ODAT,
		DOE		=>FDIBM_DOE,
		
		DSn		=>FDIBM_DSn,
		DENn	=>open,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	COM_CS<='1' when (ioaddr_even(15 downto 2)=x"003" & "00") and ioaddr_even(0)='0' else '0';
	pIDEAddress<=ioaddr_even;
	pIDESelect<=cpusel when DMAen='0' else "00";
	pIDEWriteData<=io_wdata;
	pIDERead<=iord;
	pIDEWrite<=iowr;
	pIDEResetn<=srstn;
	IDE_ODAT<=pIDEReadData;
	IDE_DOE<=pIDEOE;
	IDE_INT<=pIDEIRQ;
	
--	IDE	:pseudoide port map(
--		ioaddr	=>ioaddr,
--		iord	=>iord,
--		iowr	=>iowr,
--		rddat	=>IDE_ODAT,
--		wrdat	=>dbus,
--		doe		=>IDE_DOE,
--		int		=>IDE_INT,
--		
--		curdrive	=>open,
--		sectcount	=>open,
--		sectnum		=>open,
--		cyl			=>open,
--		dsel		=>open,
--		head		=>open,
--		
--		command		=>IDE_COMMAND,
--		commandwr	=>IDE_CMD_WR,
--		commanddone	=>IDE_CMD_ACK,
--		driveconnect=>"01",
--		seekdone	=>'1',
--		drvready	=>'1',
--		datareq		=>'0',
--		drvwrite	=>'0',
--		drvindex	=>'0',
--		drverror	=>(others=>'0'),
--		drvrddat	=>IDE_RDDAT,
--		drvwrdat	=>IDE_WRDAT,
--		drvrd		=>IDE_DRV_RD,
--		drvwr		=>IDE_DRV_WR,
--		drvrst		=>open,
--		
--		clk			=>cpuclk,
--		rstn		=>srstn
--	);
--	
--	ided	:idedrv port map(
--		command		=>IDE_COMMAND,
--		command_wr	=>IDE_CMD_WR,
--		command_ack	=>IDE_CMD_ACK,
--		rddat		=>IDE_RDDAT,
--		rd			=>IDE_DRV_RD,
--		wrdat		=>IDE_WRDAT,
--		wr			=>IDE_DRV_WR,
--		
--		clk			=>cpuclk,
--		rstn		=>srstn
--	);
	
	COM	:e8251 port map(
		WRn		=>not iowr,
		RDn		=>not iord,
		C_Dn	=>ioaddr(1),
		CSn		=>not COM_CS,
		DATIN	=>io_wdata(7 downto 0),
		DATOUT	=>COM_ODAT,
		DATOE	=>COM_DOE,
		INTn	=>COM_INTn,
		
		TXD		=>open,
		RxD		=>'1',
		
		DSRn	=>'1',
		DTRn	=>open,
		RTSn	=>open,
		CTSn	=>'1',
		
		TxRDY	=>open,
		TxEMP	=>open,
		RxRDY	=>open,
		
		TxCn	=>'1',
		RxCn	=>'1',
		
		clk		=>cpuclk,
		rstn	=>srstn
	);

	PTC_CS<='1' when ioaddr_odd(15 downto 3)=(x"007" & '0') and ioaddr_odd(0)='1' else
			'1' when ioaddr_odd(15 downto 3)=(x"3fd" & '1') and ioaddr_odd(0)='1' else
			'0';
	
	PTCCLK	:SFTCLK generic map(SYSFREQ,2458,1) port map(
		sel		=>"1",
		SFT		=>PTC_SFT,

		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	PTC	:PTC8253 port map(
		CS		=>PTC_CS,
		ADDR	=>ioaddr(2 downto 1),
		RD		=>iord,
		WR		=>iowr,
		RDAT	=>PTC_ODAT,
		WDAT	=>io_wdata(15 downto 8),
		DOE		=>PTC_DOE,
		
		CNTIN	=>PTC_SFT & PTC_SFT & PTC_SFT,
		TRIG	=>(others=>'1'),
		CNTOUT	=>PTC_CNTOUT,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);
	
	process(cpuclk,srstn)
	variable	lack	:std_logic;
	begin
		if(srstn='0')then
			IPCOUNT<=(others=>'0');
		elsif(cpuclk' event and cpuclk='1')then
			if(lack='0' and iack='1')then
				IPCOUNT<=IPCOUNT+1;
			end if;
			lack:=iack;
		end if;
	end process;
	
	
	MOUS_CS<='1' when ioaddr_odd(15 downto 3)=(x"7fd" & '1') and ioaddr_odd(0)='1' else '0';
	
	MOUSP	:e8255 port map(
		CSn		=>not MOUS_CS,
		RDn		=>not iord,
		WRn		=>not iowr,
		ADR		=>ioaddr(2 downto 1),
		DATIN	=>io_wdata(15 downto 8),
		DATOUT	=>MOUS_ODAT,
		DATOE	=>MOUS_DOE,
		
		PAi		=>MOUS_PAIN,
		PAo		=>open,
		PAoe	=>open,
		PBi		=>MOUS_PBIN,
		PBo		=>open,
		PBoe	=>open,
		PCHi	=>MOUS_PCHOUT,
		PCHo	=>MOUS_PCHOUT,
		PCHoe	=>open,
		PCLi	=>MOUS_PCLIN,
		PCLo	=>open,
		PCLoe	=>open,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);

	MOUS_PBIN<="11111111";
	MOUS_PCLIN<="1111";
	
	mous :MOUSECONV generic map(
		CLKCYC	=>SYSFREQ,
		SFTCYC	=>400
	)port map(
		HC			=>MOUS_PCHOUT(3),
		SXY		=>MOUS_PCHOUT(2),
		SHL		=>MOUS_PCHOUT(1),

		MOUSDAT	=>MOUS_PAIN,

		MCLKIN	=>pPmsClkin,
		MCLKOUT	=>pPmsClkout,
		MDATIN	=>pPmsDatin,
		MDATOUT	=>pPmsDatout,
		
		clk		=>cpuclk,
		rstn		=>srstn
	);
	
	MOUINT_CS<=	'1' when ioaddr_odd=x"bfdb" else '0';
	MOUSI	:mouseint generic map(SYSFREQ) port map(
		cs		=>MOUINT_CS,
		wr		=>iowr,
		wrdat	=>io_wdata(15 downto 8),
		
		int	=>MOUS_INTp,
		
		clk	=>cpuclk,
		rstn	=>srstn
	);
	
	MOUS_INTe<=not MOUS_PCHOUT(0);
	
	startup_sound : entity work.startup_mute
		generic map(CLOCK_KHZ => SYSFREQ)
		port map(clk => cpuclk, rstn => srstn, bypass => pStartupBeeps,
			muted => startup_muted, speaker_on => BEEPON);

	BEEP_snd<=	(others=>'0') when BEEPON='0' or startup_muted='1' else
				x"1fff" when PTC_CNTOUT(1)='1' else
				x"e000" when PTC_CNTOUT(1)='0';
	
	TSTMP_CS<=	'1' when ioaddr(15 downto 4)=x"005" and ioaddr(3 downto 2)="11" else '0';
	
	TSTMP	:tstamp generic map(SYSFREQ,3260) port map(
		addr	=>ioaddr(1),
		ce		=>TSTMP_CS,
		rd		=>iord,
		wr		=>iowr,
		rddat	=>TSTMP_ODAT,
		doe		=>TSTMP_DOE,
		waitn	=>TSTMP_WAITn,
		
		clk		=>cpuclk,
		rstn	=>srstn
	);

	-- The baseline enables OPNA at 10 MHz (20 MHz / 2). Scale the divisor
	-- with the system clock so a CPU speed experiment does not speed up music.
	OPNS	:sftgen generic map(SYSFREQ/10000) port map(SYSFREQ/10000,OPN_sft,cpuclk,srstn);
	SNDID_CS<='1' when ioaddr_even=x"a460" else '0';

	no_pcm :if SND/=3 generate
		PCM_IRQ<='0'; PCM_EXT<='1'; PCM_FM_MUTE<='0';
		PCM_L<=(others=>'0'); PCM_R<=(others=>'0');
	end generate;
	C2	:if SND=2 or SND=3 generate
		OPN_CS<=	'1' when ioaddr_even(15 downto 3)="0000000110001" and ioaddr_even(0)='0' and
			(ioaddr_even(2)='0' or PCM_EXT='1') else '0';
		
		FMS	:OPNA generic map(16) port map(
			DIN		=>io_wdata(7 downto 0),
			DOUT		=>OPN_ODAT,
			DOE		=>OPN_DOE,
			CSn		=>not OPN_CS,
			ADR	=>ioaddr(2 downto 1),
			RDn		=>not iord,
			WRn		=>not iowr,
			INTn	=>OPN_INTn,
			
			sndL		=>OPN_sndL,
			sndR		=>OPN_sndR,
			sndPSG	=>OPN_sndPSG,
			
			PAOUT	=>OPN_GPIOAo,
			PAIN	=>OPN_GPIOAi,
			PAOE	=>OPN_GPIOAoe,
			
			PBOUT	=>OPN_GPIOBo,
			PBIN	=>OPN_GPIOBi,
			PBOE	=>OPN_GPIOBoe,

			RAMADDR	=>open,
			RAMRD		=>open,
			RAMWR		=>open,
			RAMRDAT	=>(others=>'0'),
			RAMWDAT	=>open,
			RAMWAIT	=>'0',

			clk		=>cpuclk,
			cpuclk	=>cpuclk,
			sft		=>OPN_sft,
			rstn	=>srstn
		);

		FM_ROUTE_L<=OPN_sndL when PCM_FM_MUTE='0' else (others=>'0');
		FM_ROUTE_R<=OPN_sndR when PCM_FM_MUTE='0' else (others=>'0');
		PSG_ROUTE<=OPN_sndPSG when PCM_FM_MUTE='0' else (others=>'0');
		monoa	:average generic map(16) port map(BEEP_snd,PSG_ROUTE,SND_MONO);
		MIXL	:average generic map(16) port map(FM_ROUTE_L,SND_MONO,BASE_SND_L);
		MIXR	:average generic map(16) port map(FM_ROUTE_R,SND_MONO,BASE_SND_R);
		legacy_sound :if SND=2 generate
			pSndL<=BASE_SND_L; pSndR<=BASE_SND_R;
			SID :sndid generic map(x"2") port map(SNDID_CS,IORD,IOWR,SNDID_ODAT,SNDID_OE,io_wdata(7 downto 0),open,open,cpuclk,rstn);
		end generate;
		board86 :if SND=3 generate
			pcm :pcm86 generic map(CLOCK_HZ=>SYSFREQ*1000) port map(
				clk=>cpuclk, reset=>not srstn, address=>ioaddr_even,
				read=>IORD, write=>IOWR, writedata=>io_wdata(7 downto 0),
				readdata=>SNDID_ODAT, selected=>SNDID_OE, irq=>PCM_IRQ,
				opna_extended=>PCM_EXT, opna_muted=>PCM_FM_MUTE,
				audio_l=>PCM_L, audio_r=>PCM_R, sample_valid=>open
			);
			-- Preserve the existing FM/speaker gain; saturate added half-scale PCM.
			pcm_mix_l :entity work.addsat generic map(16)
				port map(BASE_SND_L,PCM_L(15) & PCM_L(15 downto 1),pSndL,open,open);
			pcm_mix_r :entity work.addsat generic map(16)
				port map(BASE_SND_R,PCM_R(15) & PCM_R(15 downto 1),pSndR,open,open);
		end generate;
		
	end generate;
	
	c1	:if SND=1 generate
		OPN_CS<=	'1' when ioaddr_even(15 downto 2)="00000001100010" and ioaddr_even(0)='0' else '0';
		
		FMS	:OPN generic map(16) port map(
			DIN		=>io_wdata(7 downto 0),
			DOUT	=>OPN_ODAT,
			DOE		=>OPN_DOE,
			CSn		=>not OPN_CS,
			ADR0	=>ioaddr(1),
			RDn		=>not iord,
			WRn		=>not iowr,
			INTn	=>OPN_INTn,
			
			snd		=>OPN_sndR,
			
			PAOUT	=>OPN_GPIOAo,
			PAIN	=>OPN_GPIOAi,
			PAOE	=>OPN_GPIOAoe,
			
			PBOUT	=>OPN_GPIOBo,
			PBIN	=>OPN_GPIOBi,
			PBOE	=>OPN_GPIOBoe,

			clk		=>cpuclk,
			cpuclk	=>cpuclk,
			sft		=>OPN_sft,
			rstn	=>srstn
		);
		
		pSndL<=BEEP_snd;
		pSndR<=OPN_sndR;
		SNDID_ODAT<=(others=>'0');
		SNDID_OE<='0';
		
	end generate;
	c0	:if SND=0 generate
		OPN_DOE<='0';
		OPN_ODAT<=x"00";
		OPN_INTn<='1';
		pSndL<=BEEP_snd;
		pSndR<=BEEP_snd;
		SNDID_ODAT<=(others=>'0');
		SNDID_OE<='0';

	end generate;
	
	OPN_GPIOAi(7 downto 6)<="11";
	OPN_GPIOAi(5 downto 0)<=pJoyA when OPN_GPIOBo(6)='0' else pJoyB;
	
	
end rtl;

