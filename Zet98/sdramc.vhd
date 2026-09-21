LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY SDRAMC IS
	generic(
		ADRWIDTH		:integer	:=23;
		CLKMHZ			:integer	:=100;			--MHz
		REFCYC			:integer	:=64000/8192	--usec
	);
	port(
		-- SDRAM PORTS
		PMEMCKE			: OUT	STD_LOGIC;							-- SD-RAM CLOCK ENABLE
		PMEMCS_N			: OUT	STD_LOGIC;							-- SD-RAM CHIP SELECT
		PMEMRAS_N		: OUT	STD_LOGIC;							-- SD-RAM ROW/RAS
		PMEMCAS_N		: OUT	STD_LOGIC;							-- SD-RAM /CAS
		PMEMWE_N			: OUT	STD_LOGIC;							-- SD-RAM /WE
		PMEMUDQ			: OUT	STD_LOGIC;							-- SD-RAM UDQM
		PMEMLDQ			: OUT	STD_LOGIC;							-- SD-RAM LDQM
		PMEMBA1			: OUT	STD_LOGIC;							-- SD-RAM BANK SELECT ADDRESS 1
		PMEMBA0			: OUT	STD_LOGIC;							-- SD-RAM BANK SELECT ADDRESS 0
		PMEMADR			: OUT	STD_LOGIC_VECTOR( 12 DOWNTO 0 );	-- SD-RAM ADDRESS
		PMEMDAT			: INOUT	STD_LOGIC_VECTOR( 15 DOWNTO 0 );	-- SD-RAM DATA

		CPUBNK			:in std_logic_vector(1 downto 0);
		CPUADR			:in std_logic_vector(ADRWIDTH-1 downto 0);
		CPURDAT0			:out std_logic_vector(15 downto 0);
		CPURDAT1			:out std_logic_vector(15 downto 0);
		CPURDAT2			:out std_logic_vector(15 downto 0);
		CPURDAT3			:out std_logic_vector(15 downto 0);
		CPUWDAT0			:in std_logic_vector(15 downto 0);
		CPUWDAT1			:in std_logic_vector(15 downto 0);
		CPUWDAT2			:in std_logic_vector(15 downto 0);
		CPUWDAT3			:in std_logic_vector(15 downto 0);
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
		SUBRDAT0			:out std_logic_vector(15 downto 0);
		SUBRDAT1			:out std_logic_vector(15 downto 0);
		SUBRDAT2			:out std_logic_vector(15 downto 0);
		SUBRDAT3			:out std_logic_vector(15 downto 0);
		SUBWDAT0			:in std_logic_vector(15 downto 0);
		SUBWDAT1			:in std_logic_vector(15 downto 0);
		SUBWDAT2			:in std_logic_vector(15 downto 0);
		SUBWDAT3			:in std_logic_vector(15 downto 0);
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
		VIDRD				:in std_logic;
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
end SDRAMC;

architecture MAIN of SDRAMC is
type state_t is (
	ST_INITPALL,
	ST_INITREF,
	ST_INITMRS,
	ST_REFRESH,
	ST_READ,
	ST_READ4,
	ST_WRITE,
	ST_WRITE4,
	ST_RMW,
	ST_RMW4,
	ST_SUBREAD,
	ST_SUBREAD4,
	ST_SUBWRITE,
	ST_SUBWRITE4,
	ST_SUBRMW,
	ST_SUBRMW4,
	ST_VIDREAD,
	ST_FDEREAD,
	ST_FDEWRITE,
	ST_FECREAD,
	ST_FECWRITE
);
signal	STATE,lSTATE	:state_t;

constant INITR_TIMES	:integer	:=20;
signal	INITR_COUNT	:integer range 0 to INITR_TIMES;
constant INITTIMERCNT:integer	:=1000;
signal	INITTIMER	:integer range 0 to INITTIMERCNT;
--constant clockwtime	:integer	:=50000;	--usec
constant clockwtime	:integer	:=2;	--usec
constant cwaitcnt	:integer	:=clockwtime*86;	--clocks
signal	CLOCKWAIT	:integer range 0 to cwaitcnt;
signal	clkcount,lclkcount	:integer range 0 to 20;
constant allzero	:std_logic_vector(12 downto 0)	:=(others=>'0');

constant REFINT		:integer	:=CLKMHZ*REFCYC/20;
signal	REFCNT	:integer range 0 to REFINT-1;

signal	lcpustb		:std_logic;
signal	lsubstb		:std_logic;
signal	lvidstb		:std_logic;
signal	lfdestb		:std_logic;
signal	lfecstb		:std_logic;
signal	cpuend		:std_logic;
signal	subend		:std_logic;
signal	vidend		:std_logic;
signal	fdeend		:std_logic;
signal	fecend		:std_logic;
signal	CPUACKb		:std_logic;
signal	SUBACKb		:std_logic;
signal	VIDACKb		:std_logic;
signal	FDEACKb		:std_logic;
signal	FECACKb		:std_logic;
signal	lCPUREQ		:std_logic_vector(2 downto 0);
signal	lSUBREQ		:std_logic_vector(2 downto 0);
signal	lVIDREQ		:std_logic_vector(2 downto 0);
signal	lFDEREQ		:std_logic_vector(2 downto 0);
signal	lFECREQ		:std_logic_vector(2 downto 0);
signal	lCPUADR		:std_logic_vector(ADRWIDTH-1 downto 0);
signal	lCPUBNK,lCPUBSEL :std_logic_vector(1 downto 0);
signal	lCPUPSEL :std_logic_vector(3 downto 0);
signal	lFDEADR		:std_logic_vector(ADRWIDTH+1 downto 0);
signal	lFECADR		:std_logic_vector(ADRWIDTH+1 downto 0);
signal	smemdat		:std_logic_vector(15 downto 0);

type job_t is(
	JOB_NOP,
	JOB_RD,
	JOB_RD4,
	JOB_WR,
	JOB_WR4,
	JOB_RMW,
	JOB_RMW4
);

signal	CPUJOB,nCPUJOB	:job_t;
signal	SUBJOB,nSUBJOB	:job_t;
signal	VIDJOB	:job_t;
signal	FDEJOB,nFDEJOB,lFDEJOB	:job_t;
signal	FECJOB,nFECJOB	:job_t;
signal	CPUREQ,CPUREC	:std_logic;
signal	SUBREQ,SUBREC	:std_logic;
-- One outstanding graphics transfer. Request and completion are toggles,
-- so a pulse or the previous acknowledgement cannot be sampled as a new job.
signal VIDREQ, VIDbusy : std_logic;
signal VIDdone_sync : std_logic_vector(1 downto 0);
attribute preserve : boolean;
attribute preserve of lVIDREQ, VIDdone_sync : signal is true;
attribute altera_attribute : string;
attribute altera_attribute of lVIDREQ, VIDdone_sync : signal is
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
signal	FDEREQ,FDEREC	:std_logic;
signal	FECREQ,FECREC	:std_logic;

signal	isCPU		:std_logic;

signal	MEMCKE		:STD_LOGIC;							-- SD-RAM CLOCK ENABLE
signal	MEMCS_N		:STD_LOGIC;							-- SD-RAM CHIP SELECT
signal	MEMRAS_N	:STD_LOGIC;							-- SD-RAM ROW/RAS
signal	MEMCAS_N	:STD_LOGIC;							-- SD-RAM /CAS
signal	MEMWE_N		:STD_LOGIC;							-- SD-RAM /WE
signal	MEMUDQ		:STD_LOGIC;							-- SD-RAM UDQM
signal	MEMLDQ		:STD_LOGIC;							-- SD-RAM LDQM
signal	MEMBA1		:STD_LOGIC;							-- SD-RAM BANK SELECT ADDRESS 1
signal	MEMBA0		:STD_LOGIC;							-- SD-RAM BANK SELECT ADDRESS 0
signal	MEMADR		:STD_LOGIC_VECTOR( 12 DOWNTO 0 );	-- SD-RAM ADDRESS
signal	MEMDAT		:STD_LOGIC_VECTOR( 15 DOWNTO 0 );	-- SD-RAM DATA
signal	MEMDATOE	:STD_LOGIC;

signal	SUBREQS	:std_logic;
begin

	process(memclk,rstn)
	variable	st_next	:std_logic;
	begin
		if(rstn='0')then
			MEMCKE		<='0';
			MEMCS_N		<='1';
			MEMRAS_N	<='1';
			MEMCAS_N	<='1';
			MEMWE_N		<='1';
			MEMUDQ		<='1';
			MEMLDQ		<='1';
			MEMBA1		<='0';
			MEMBA0		<='0';
			MEMADR		<=(others=>'0');
			MEMDAT		<=(others=>'0');
			MEMDATOE	<='0';
			STATE		<=ST_INITPALL;
			INITR_COUNT	<=INITR_TIMES;
			INITTIMER	<=INITTIMERCNT;
			CLOCKWAIT	<=cwaitcnt;
			clkcount	<=0;
			REFCNT		<=REFINT-1;
			CPUJOB		<=JOB_NOP;
			SUBJOB		<=JOB_NOP;
			VIDJOB		<=JOB_NOP;
			FDEJOB		<=JOB_NOP;
			FECJOB		<=JOB_NOP;
			
			isCPU<='0';
			cpuend<='0';
			subend<='0';
			vidend<='0';
			lCPUREQ<=(others=>'0');
			lSUBREQ<=(others=>'0');
			lVIDREQ<=(others=>'0');
			lFDEREQ<=(others=>'0');
			lFECREQ<=(others=>'0');
			CPUREC<='0';
			SUBREC<='0';
			FDEREC<='0';
			FECREC<='0';
			mem_inidone<='0';
		elsif(memclk' event and memclk='1')then
			lCPUREQ<=lCPUREQ(1 downto 0) & CPUREQ;
			lSUBREQ<=lSUBREQ(1 downto 0) & SUBREQ;
			lVIDREQ<=lVIDREQ(1 downto 0) & VIDREQ;
			lFDEREQ<=lFDEREQ(1 downto 0) & FDEREQ;
			lFECREQ<=lFECREQ(1 downto 0) & FECREQ;
			st_next:='0';
			if(clkcount=0 and REFCNT>0)then
				REFCNT<=REFCNT-1;
			end if;
			if(lCPUREQ="011")then
				CPUJOB<=nCPUJOB;
				CPUREC<='1';
			elsif(CPUREQ='0')then
				CPUREC<='0';
			end if;
			if(lSUBREQ="011")then
				SUBJOB<=nSUBJOB;
				SUBREC<='1';
			elsif(SUBREQ='0')then
				SUBREC<='0';
			end if;
			if(lVIDREQ(2)/=lVIDREQ(1))then
				VIDJOB<=JOB_RD;
			end if;
			if(lFDEREQ="011")then
				FDEJOB<=nFDEJOB;
				FDEREC<='1';
			elsif(FDEREQ='0')then
				FDEREC<='0';
			end if;
			if(lFECREQ="011")then
				FECJOB<=nFECJOB;
				FECREC<='1';
			elsif(FECREQ='0')then
				FECREC<='0';
			end if;
			
--			if(nCPUJOB/=JOB_NOP)then
--				lCPUNOP(0)<='0';
--				if(lCPUNOP="10")then
--					CPUJOB<=nCPUJOB;
--				end if;
--			else
--				lCPUNOP(0)<='1';
--			end if;
--			if(nSUBJOB/=JOB_NOP)then
--			lSUBNOP(0)<='0';
--				if(lSUBNOP="10")then
--					SUBJOB<=nSUBJOB;
--				end if;
--			else
--				lSUBNOP(0)<='1';
--			end if;
--			if(nVIDJOB/=JOB_NOP)then
--				lVIDNOP(0)<='1';
--				if(lVIDNOP="10")then
--					VIDJOB<=nVIDJOB;
--				end if;
--			else
--				lVIDNOP(0)<='0';
--			end if;
			if(CPUACKb='1')then
				cpuend<='0';
			end if;
			if(SUBACKb='1')then
				subend<='0';
			end if;

			if(FDEACKb='1')then
				fdeend<='0';
			end if;
			if(FECACKb='1')then
				fecend<='0';
			end if;
			
			if(INITTIMER>0)then
				if(INITTIMER=1)then
					MEMCKE<='1';
					CLOCKWAIT<=cwaitcnt;
				else
					MEMCKE<='0';
				end if;
				INITTIMER<=INITTIMER-1;
			elsif(CLOCKWAIT>0)then
				CLOCKWAIT<=CLOCKWAIT-1;
				clkcount<=0;
				STATE<=ST_INITPALL;
			else
				case STATE is
				when ST_INITPALL =>
					case clkcount is
					when 0 =>	--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 3 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_INITREF | ST_REFRESH =>
					case clkcount is
					when 0 =>
						REFCNT		<=REFINT-1;
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 6 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_INITMRS =>
					case clkcount is
					when 0 =>
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<="0000000100010";	-- 4 word burst, CAS2
						MEMDATOE	<='0';
					when 2 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_READ =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=lCPUADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<="000" & lCPUADR(9 downto 0);
						MEMDATOE	<='0';
					when 3 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 6 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_READ4 =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=lCPUADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<="000" & lCPUADR(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>	--DQ
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 6 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 9 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 11 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_WRITE =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=lCPUADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not lCPUBSEL(1);
						MEMLDQ		<=not lCPUBSEL(0);
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not lCPUBSEL(1) & not lCPUBSEL(0);
						MEMADR(10 downto 0)	<='0' & lCPUADR(9 downto 0);
						MEMDAT		<=CPUWDAT0;
						MEMDATOE	<='1';
					when 3 =>		--break burst and precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 5 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_WRITE4 =>
					case clkcount is
					when 0 =>
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=lCPUADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (lCPUPSEL(0) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(0) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(0) and lCPUBSEL(1)) & not (lCPUPSEL(0) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<='0' & lCPUADR(9 downto 2) & "00";
						MEMDAT		<=CPUWDAT0;
						MEMDATOE	<='1';
					when 3 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (lCPUPSEL(1) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(1) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(1) and lCPUBSEL(1)) & not (lCPUPSEL(1) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=CPUWDAT1;
						MEMDATOE	<='1';
					when 4 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (lCPUPSEL(2) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(2) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(2) and lCPUBSEL(1)) & not (lCPUPSEL(2) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=CPUWDAT2;
						MEMDATOE	<='1';
					when 5 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (lCPUPSEL(3) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(3) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(3) and lCPUBSEL(1)) & not (lCPUPSEL(3) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=CPUWDAT3;
						MEMDATOE	<='1';
					when 6 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 8 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_RMW =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=lCPUADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<="000" & lCPUADR(9 downto 0);
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN(Hi-Z)
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not lCPUBSEL(1);
						MEMLDQ		<=not lCPUBSEL(0);
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not lCPUBSEL(1) & not lCPUBSEL(0);
						MEMADR(10 downto 0)	<='0' & lCPUADR(9 downto 0);
						MEMDAT		<=CPUWDAT0;
						MEMDATOE	<='1';
					when 9 =>		--break burst and precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 11 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_RMW4 =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=lCPUADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<="000" & lCPUADR(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 6 =>				--BST
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (lCPUPSEL(0) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(0) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(0) and lCPUBSEL(1)) & not (lCPUPSEL(0) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<='0' & lCPUADR(9 downto 0);
						MEMDAT		<=CPUWDAT0;
						MEMDATOE	<='1';
					when 9 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (lCPUPSEL(1) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(1) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(1) and lCPUBSEL(1)) & not (lCPUPSEL(1) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=CPUWDAT1;
						MEMDATOE	<='1';
					when 10 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (lCPUPSEL(2) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(2) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(2) and lCPUBSEL(1)) & not (lCPUPSEL(2) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=CPUWDAT2;
						MEMDATOE	<='1';
					when 11 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (lCPUPSEL(3) and lCPUBSEL(1));
						MEMLDQ		<=not (lCPUPSEL(3) and lCPUBSEL(0));
						MEMBA1		<=lCPUBNK(1);
						MEMBA0		<=lCPUBNK(0);
						MEMADR(12 downto 11)	<=not (lCPUPSEL(3) and lCPUBSEL(1)) & not (lCPUPSEL(3) and lCPUBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=CPUWDAT3;
						MEMDATOE	<='1';
					when 12 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 14 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
					
				when ST_SUBREAD =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=SUBADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<="000" & SUBADR(9 downto 0);
						MEMDATOE	<='0';
					when 3 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 6 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_SUBREAD4 =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=SUBADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<="000" & SUBADR(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>	--DQ
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 6 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 9 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 11 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_SUBWRITE =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=SUBADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not SUBBSEL(1);
						MEMLDQ		<=not SUBBSEL(0);
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not SUBBSEL(1) & not SUBBSEL(0);
						MEMADR(10 downto 0)	<='0' & SUBADR(9 downto 0);
						MEMDAT		<=SUBWDAT0;
						MEMDATOE	<='1';
					when 3 =>		--break burst and precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 5 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_SUBWRITE4 =>
					case clkcount is
					when 0 =>
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=SUBADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (SUBPSEL(0) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(0) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(0) and SUBBSEL(1)) & not (SUBPSEL(0) and SUBBSEL(0));
						MEMADR(10 downto 0)	<='0' & SUBADR(9 downto 2) & "00";
						MEMDAT		<=SUBWDAT0;
						MEMDATOE	<='1';
					when 3 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (SUBPSEL(1) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(1) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(1) and SUBBSEL(1)) & not (SUBPSEL(1) and SUBBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=SUBWDAT1;
						MEMDATOE	<='1';
					when 4 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (SUBPSEL(2) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(2) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(2) and SUBBSEL(1)) & not (SUBPSEL(2) and SUBBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=SUBWDAT2;
						MEMDATOE	<='1';
					when 5 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (SUBPSEL(3) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(3) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(3) and SUBBSEL(1)) & not (SUBPSEL(3) and SUBBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=SUBWDAT3;
						MEMDATOE	<='1';
					when 6 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 8 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_SUBRMW =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=SUBADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<="000" & SUBADR(9 downto 0);
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN(Hi-Z)
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not SUBBSEL(1);
						MEMLDQ		<=not SUBBSEL(0);
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not SUBBSEL(1) & not SUBBSEL(0);
						MEMADR(10 downto 0)	<='0' & SUBADR(9 downto 0);
						MEMDAT		<=SUBWDAT0;
						MEMDATOE	<='1';
					when 9 =>		--break burst and precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 11 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_SUBRMW4 =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=SUBADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<="000" & SUBADR(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 11 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (SUBPSEL(0) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(0) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(0) and SUBBSEL(1)) & not (SUBPSEL(0) and SUBBSEL(0));
						MEMADR(10 downto 0)	<='0' & SUBADR(9 downto 0);
						MEMDAT		<=SUBWDAT0;
						MEMDATOE	<='1';
					when 12 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (SUBPSEL(1) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(1) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(1) and SUBBSEL(1)) & not (SUBPSEL(1) and SUBBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=SUBWDAT1;
						MEMDATOE	<='1';
					when 13 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (SUBPSEL(2) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(2) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(2) and SUBBSEL(1)) & not (SUBPSEL(2) and SUBBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=SUBWDAT2;
						MEMDATOE	<='1';
					when 14 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (SUBPSEL(3) and SUBBSEL(1));
						MEMLDQ		<=not (SUBPSEL(3) and SUBBSEL(0));
						MEMBA1		<=SUBBNK(1);
						MEMBA0		<=SUBBNK(0);
						MEMADR(12 downto 11)	<=not (SUBPSEL(3) and SUBBSEL(1)) & not (SUBPSEL(3) and SUBBSEL(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=SUBWDAT3;
						MEMDATOE	<='1';
					when 15 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 17 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_VIDREAD =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=VIDBNK(1);
						MEMBA0		<=VIDBNK(0);
						MEMADR		<=VIDADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						VIDJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=VIDBNK(1);
						MEMBA0		<=VIDBNK(0);
						MEMADR		<="000" & VIDADR(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>	--DQ
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=VIDBNK(1);
						MEMBA0		<=VIDBNK(0);
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 6 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 9 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 11 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_FDEREAD =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=FDEADR(ADRWIDTH+1);
						MEMBA0		<=FDEADR(ADRWIDTH);
						MEMADR		<=FDEADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						FDEJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=FDEADR(ADRWIDTH+1);
						MEMBA0		<=FDEADR(ADRWIDTH);
						MEMADR		<="000" & FDEADR(9 downto 0);
						MEMDATOE	<='0';
					when 3 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 6 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_FDEWRITE =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=FDEADR(ADRWIDTH+1);
						MEMBA0		<=FDEADR(ADRWIDTH);
						MEMADR		<=FDEADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						FDEJOB<=JOB_NOP;
					when 2 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=FDEADR(ADRWIDTH+1);
						MEMBA0		<=FDEADR(ADRWIDTH);
						MEMADR		<="000" & FDEADR(9 downto 0);
						MEMDAT		<=FDEWDAT;
						MEMDATOE	<='1';
					when 3 =>		--break burst and precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 5 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_FECREAD =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=FECADR(ADRWIDTH+1);
						MEMBA0		<=FECADR(ADRWIDTH);
						MEMADR		<=FECADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						FECJOB<=JOB_NOP;
					when 2 =>		--read command
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=FECADR(ADRWIDTH+1);
						MEMBA0		<=FECADR(ADRWIDTH);
						MEMADR		<="000" & FECADR(9 downto 0);
						MEMDATOE	<='0';
					when 3 =>		--precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 6 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when ST_FECWRITE =>
					case clkcount is
					when 0 =>		--active bank
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=FECADR(ADRWIDTH+1);
						MEMBA0		<=FECADR(ADRWIDTH);
						MEMADR		<=FECADR(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						FECJOB<=JOB_NOP;
					when 2 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=FECADR(ADRWIDTH+1);
						MEMBA0		<=FECADR(ADRWIDTH);
						MEMADR		<="000" & FECADR(9 downto 0);
						MEMDAT		<=FECWDAT;
						MEMDATOE	<='1';
					when 3 =>		--break burst and precharge all
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='0';
						MEMCAS_N	<='1';
						MEMWE_N		<='0';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR		<=(others=>'1');
						MEMDATOE	<='0';
					when 5 =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
						st_next:='1';
					when others =>
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<='0';
						MEMBA0		<='0';
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					end case;
				when others =>
					st_next:='1';
				end case;
				if(st_next='1')then		--select next state
					case STATE is
					when ST_READ | ST_READ4 | ST_WRITE | ST_WRITE4 | ST_RMW | ST_RMW4 =>
						cpuend<='1';
					when ST_SUBREAD | ST_SUBREAD4 | ST_SUBWRITE | ST_SUBWRITE4 | ST_SUBRMW | ST_SUBRMW4 =>
						subend<='1';
					when ST_VIDREAD =>
						vidend<=lVIDREQ(2);
					when ST_FDEREAD | ST_FDEWRITE =>
						fdeend<='1';
					when ST_FECREAD | ST_FECWRITE =>
						fecend<='1';
					when others =>
					end case;
					case STATE is
					when ST_INITPALL =>
						STATE<=ST_INITREF;
						INITR_COUNT<=INITR_TIMES;
					when ST_INITREF =>
						if(INITR_COUNT>0)then
							INITR_COUNT<=INITR_COUNT-1;
						else
							STATE<=ST_INITMRS;
						end if;
					when ST_INITMRS =>
						STATE<=ST_REFRESH;
						mem_inidone<='1';
--					when ST_READ | ST_READ4| ST_WRITE | ST_WRITE4 | ST_RMW | ST_RMW4 |
--							ST_SUBREAD | ST_SUBREAD4 | ST_SUBWRITE | ST_SUBWRITE4 |ST_SUBRMW | ST_SUBRMW4 |
--							ST_FDEREAD | ST_FDEWRITE | ST_FECREAD | ST_FECWRITE =>
--						if(VIDJOB=JOB_NOP)then
--							STATE<=ST_REFRESH;
--						else
--							STATE<=ST_VIDREAD;
--						end if;
					when others =>
						if(REFCNT=0)then
							STATE<=ST_REFRESH;
						elsif(VIDJOB/=JOB_NOP)then
							STATE<=ST_VIDREAD;
						elsif(FDEJOB/=JOB_NOP)then
							case FDEJOB is
							when JOB_RD =>
								STATE<=ST_FDEREAD;
							when JOB_WR =>
								STATE<=ST_FDEWRITE;
							when others =>
								STATE<=ST_REFRESH;
							end case;
							isCPU<='1';
						elsif((isCPU='0' or SUBJOB=JOB_NOP) and CPUJOB/=JOB_NOP)then
							case CPUJOB is
							when JOB_RD =>
								STATE<=ST_READ;
							when JOB_RD4 =>
								STATE<=ST_READ4;
							when JOB_WR =>
								STATE<=ST_WRITE;
							when JOB_WR4 =>
								STATE<=ST_WRITE4;
							when JOB_RMW =>
								STATE<=ST_RMW;
							when JOB_RMW4 =>
								STATE<=ST_RMW4;
							when others =>
								STATE<=ST_REFRESH;
							end case;
							isCPU<='1';
						elsif((isCPU='1' or CPUJOB=JOB_NOP) and SUBJOB/=JOB_NOP)then
							case SUBJOB is
							when JOB_RD =>
								STATE<=ST_SUBREAD;
							when JOB_RD4 =>
								STATE<=ST_SUBREAD4;
							when JOB_WR =>
								STATE<=ST_SUBWRITE;
							when JOB_WR4 =>
								STATE<=ST_SUBWRITE4;
							when JOB_RMW =>
								STATE<=ST_SUBRMW;
							when JOB_RMW4 =>
								STATE<=ST_SUBRMW4;
							when others =>
								STATE<=ST_REFRESH;
							end case;
							isCPU<='0';
						elsif(FECJOB/=JOB_NOP)then
							case FECJOB is
							when JOB_RD =>
								STATE<=ST_FECREAD;
							when JOB_WR =>
								STATE<=ST_FECWRITE;
							when others =>
								STATE<=ST_REFRESH;
							end case;
						else
							STATE<=ST_REFRESH;
						end if;
					end case;
					clkcount<=0;
				else
					clkcount<=clkcount+1;
				end if;
			end if;
		end if;
	end process;

	process(memclk)begin
		if(memclk' event and memclk='1')then
			smemdat<=pMEMDAT;
		end if;
	end process;
	
	process(memclk,rstn)begin
		if(rstn='0')then
			CPURDAT0	<=(others=>'0');
			CPURDAT1	<=(others=>'0');
			CPURDAT2	<=(others=>'0');
			CPURDAT3	<=(others=>'0');
			SUBRDAT0	<=(others=>'0');
			SUBRDAT1	<=(others=>'0');
			SUBRDAT2	<=(others=>'0');
			SUBRDAT3	<=(others=>'0');
			VIDDAT0		<=(others=>'0');
			VIDDAT1		<=(others=>'0');
			VIDDAT2		<=(others=>'0');
			VIDDAT3		<=(others=>'0');
			FDERDAT		<=(others=>'0');
			FECRDAT		<=(others=>'0');
			lSTATE		<=ST_REFRESH;
			lclkcount	<=clkcount;
		elsif(memclk' event and memclk='1')then
			case lSTATE is
			when ST_READ | ST_RMW =>
				if(lclkcount=6)then
					CPURDAT0<=SMEMDAT;
				end if;
			when ST_READ4 | ST_RMW4 =>
				case lclkcount is
				when 6 =>
					CPURDAT0<=SMEMDAT;
				when 7 =>
					CPURDAT1<=SMEMDAT;
				when 8 =>
					CPURDAT2<=SMEMDAT;
				when 9 =>
					CPURDAT3<=SMEMDAT;
				when others =>
				end case;
			when ST_SUBREAD |ST_SUBRMW =>
				if(lclkcount=6)then
					SUBRDAT0<=SMEMDAT;
				end if;
			when ST_SUBREAD4 | ST_SUBRMW4 =>
				case lclkcount is
				when 6 =>
					SUBRDAT0<=SMEMDAT;
				when 7 =>
					SUBRDAT1<=SMEMDAT;
				when 8 =>
					SUBRDAT2<=SMEMDAT;
				when 9 =>
					SUBRDAT3<=SMEMDAT;
				when others =>
				end case;
			when ST_VIDREAD =>
				case lclkcount is
				when 6 =>
					VIDDAT0<=SMEMDAT;
				when 7 =>
					VIDDAT1<=SMEMDAT;
				when 8 =>
					VIDDAT2<=SMEMDAT;
				when 9 =>
					VIDDAT3<=SMEMDAT;
				when others =>
				end case;
			when ST_FDEREAD =>
				if(lclkcount=6)then
					FDERDAT<=SMEMDAT;
				end if;
			when ST_FECREAD =>
				if(lclkcount=6)then
					FECRDAT<=SMEMDAT;
				end if;
			when others =>
			end case;
			lclkcount<=clkcount;
			lSTATE<=STATE;
		end if;
	end process;

	process(memclk)begin
		if(memclk' event and memclk='1')then
			PMEMCKE		<=MEMCKE;
			PMEMCS_N	<=MEMCS_N;
			PMEMRAS_N	<=MEMRAS_N;
			PMEMCAS_N	<=MEMCAS_N;
			PMEMWE_N	<=MEMWE_N;
			PMEMUDQ		<=MEMUDQ;
			PMEMLDQ		<=MEMLDQ;
			PMEMBA1		<=MEMBA1;
			PMEMBA0		<=MEMBA0;
			PMEMADR		<=MEMADR;
			if(MEMDATOE='1')then
				PMEMDAT		<=MEMDAT;
			else
				PMEMDAT		<=(others=>'Z');
			end if;
		end if;
	end process;
	
	process(CPUCLK,rstn)begin
		if(rstn='0')then
			lCPUADR<=(others=>'0');
			lCPUBNK<=(others=>'0');
			lCPUBSEL<=(others=>'0');
			lCPUPSEL<=(others=>'0');
			nCPUJOB<=JOB_NOP;
			lcpustb<='0';
			CPUACKb<='0';
			CPUREQ<='0';
		elsif(CPUCLK' event and CPUCLK='1')then
            -- Capture request metadata in its source clock domain before the
            -- existing request synchronizer admits the job to SDRAM. Avoid
            -- live CPU/DMA address-decode paths feeding the 100 MHz pins.
            -- RMW write data deliberately stays live: it depends on this
            -- transaction's returned graphics-plane data.
            if (CPUWR1 or CPUWR4 or CPURD1 or CPURD4 or CPURMW1 or CPURMW4)='1'
               and (lcpustb='0' or lCPUADR/=CPUADR) then
                lCPUBNK<=CPUBNK; lCPUBSEL<=CPUBSEL; lCPUPSEL<=CPUPSEL;
            end if;
--			nCPUJOB<=JOB_NOP;
			if(CPUWR1='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_WR;
					CPUREQ<='1';
				end if;
			elsif(CPUWR4='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_WR4;
					CPUREQ<='1';
				end if;
			elsif(CPURD1='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RD;
					CPUREQ<='1';
				end if;
			elsif(CPURD4='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RD4;
					CPUREQ<='1';
				end if;
			elsif(CPURMW1='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RMW;
					CPUREQ<='1';
				end if;
			elsif(CPURMW4='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RMW4;
					CPUREQ<='1';
				end if;
			else
				lcpustb<='0';
			end if;
			if(CPUREC='1')then
				nCPUJOB<=JOB_NOP;
				CPUREQ<='0';
			end if;
			if(cpuend='1')then
				CPUACKb<='1';
			else
				CPUACKb<='0';
			end if;
		end if;
	end process;
	
	SUBREQS<=SUBWR1 or SUBWR4 or SUBRD1 or SUBRD4 or SUBRMW1 or SUBRMW4;
	
	process(SUBCLK,rstn)begin
		if(rstn='0')then
			nSUBJOB<=JOB_NOP;
			lsubstb<='0';
			SUBACKb<='0';
			SUBREQ<='0';
		elsif(SUBCLK' event and SUBCLK='1')then
--			nSUBJOB<=JOB_NOP;
			if(SUBWR1='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_WR;
					SUBREQ<='1';
				end if;
			elsif(SUBWR4='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_WR4;
					SUBREQ<='1';
				end if;
			elsif(SUBRD1='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RD;
					SUBREQ<='1';
				end if;
			elsif(SUBRD4='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RD4;
					SUBREQ<='1';
				end if;
			elsif(SUBRMW1='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RMW;
					SUBREQ<='1';
				end if;
			elsif(SUBRMW4='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RMW4;
					SUBREQ<='1';
				end if;
			else
				lsubstb<='0';
			end if;
			if(SUBREC='1')then
				nSUBJOB<=JOB_NOP;
				SUBREQ<='0';
			end if;
			if(SUBend='1')then
				SUBACKb<='1';
			elsif(SUBREQS='0')then
				SUBACKb<='0';
			end if;
		end if;
	end process;

	-- GRAMADR remains stable from request through acknowledgement. Data
	-- remains stable until the next request; only the completion toggle crosses
	-- the synchronizer. The graphics reader then registers its RAM write enable.
	process(VIDCLK,rstn)begin
		if(rstn='0')then
			lVIDstb<='0';
			VIDACKb<='0';
			VIDREQ<='0';
			VIDbusy<='0';
			VIDdone_sync<=(others=>'0');
		elsif(VIDCLK' event and VIDCLK='1')then
			VIDdone_sync<=VIDdone_sync(0) & vidend;
			if(VIDRD='0')then
				lVIDstb<='0';
				VIDACKb<='0';
			elsif(lVIDstb='0')then
				lVIDstb<='1';
				VIDREQ<=not VIDREQ;
				VIDbusy<='1';
				VIDACKb<='0';
			elsif(VIDbusy='1' and VIDdone_sync(1)=VIDREQ)then
				VIDACKb<='1';
				VIDbusy<='0';
			end if;
		end if;
	end process;

	process(FDECLK,rstn)begin
		if(rstn='0')then
			lFDEADR<=(others=>'0');
			nFDEJOB<=JOB_NOP;
			lFDEJOB<=JOB_NOP;
			lfdestb<='0';
			FDEACKb<='0';
			FDEREQ<='0';
			FDEWAIT<='0';
		elsif(FDECLK' event and FDECLK='1')then
			if(FDEWR='1')then
				lfdestb<='1';
				if(lfdestb='0' or lFDEADR/=FDEADR or lFDEJOB/=JOB_WR)then
					lFDEADR<=FDEADR;
					nFDEJOB<=JOB_WR;
					lFDEJOB<=JOB_WR;
					FDEREQ<='1';
					FDEWAIT<='1';
				end if;
			elsif(FDERD='1')then
				lfdestb<='1';
				if(lfdestb='0' or lFDEADR/=FDEADR or lFDEJOB/=JOB_RD)then
					lFDEADR<=FDEADR;
					nFDEJOB<=JOB_RD;
					lFDEJOB<=JOB_RD;
					FDEREQ<='1';
					FDEWAIT<='1';
				end if;
			else
				lfdestb<='0';
			end if;
			if(FDEREC='1')then
				nFDEJOB<=JOB_NOP;
				FDEREQ<='0';
			end if;
			if(fdeend='1')then
				FDEACKb<='1';
				FDEWAIT<='0';
			else
				FDEACKb<='0';
			end if;
		end if;
	end process;

	process(FECCLK,rstn)begin
		if(rstn='0')then
			lFECADR<=(others=>'0');
			nFECJOB<=JOB_NOP;
			lfecstb<='0';
			FECACKb<='0';
			FECREQ<='0';
			FECWAIT<='0';
		elsif(FECCLK' event and FECCLK='1')then
			if(FECWR='1')then
				lfecstb<='1';
				if(lfecstb='0' or lFECADR/=FECADR)then
					lFECADR<=FECADR;
					nFECJOB<=JOB_WR;
					FECREQ<='1';
					FECWAIT<='1';
				end if;
			elsif(FECRD='1')then
				lfecstb<='1';
				if(lfecstb='0' or lFECADR/=FECADR)then
					lFECADR<=FECADR;
					nFECJOB<=JOB_RD;
					FECREQ<='1';
					FECWAIT<='1';
				end if;
			else
				lfecstb<='0';
			end if;
			if(FECREC='1')then
				nFECJOB<=JOB_NOP;
				FECREQ<='0';
			end if;
			if(fecend='1')then
				FECACKb<='1';
				FECWAIT<='0';
			else
				FECACKb<='0';
			end if;
		end if;
	end process;

	CPUACK<=CPUACKb;
	SUBACK<=SUBACKb;
	VIDACK<=VIDACKb;
--	FDEACK<=FDEACKb;
--	FECACK<=FECACKb;

end MAIN;
