LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY SDRAMC IS
	generic(
		ADRWIDTH		:integer	:=23;
		CLKMHZ			:integer	:=100;			--MHz
		REFCYC			:integer	:=64000/8192;	--usec
        CPU_WRITE_BUNDLE : boolean := false;
        SUB_WRITE_BUNDLE : boolean := false;
        FLOPPY_REQUEST_BUNDLE : boolean := false;
        CPU_AFFINE_RMW : boolean := false
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
		SUBRDAT0			:out std_logic_vector(15 downto 0);
		SUBRDAT1			:out std_logic_vector(15 downto 0);
		SUBRDAT2			:out std_logic_vector(15 downto 0);
		SUBRDAT3			:out std_logic_vector(15 downto 0);
		SUBWDAT0			:in std_logic_vector(15 downto 0);
		SUBWDAT1			:in std_logic_vector(15 downto 0);
		SUBWDAT2			:in std_logic_vector(15 downto 0);
		SUBWDAT3			:in std_logic_vector(15 downto 0);
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
		rstn			:in std_logic;
        -- Optional EGC coefficients, sampled with the CPU request.
        -- They apply only to CPU four-plane RMW transactions.
        CPUAFFINE :in std_logic := '0';
        CPUXORMASK :in std_logic_vector(63 downto 0) := (others=>'0')
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
-- Request and completion toggles permit unrelated CPU/SUB and memory clocks.
-- Two destination flops isolate completion before ACK/data capture. This adds
-- two source-clock waits but removes the short adjacent-PLL-edge control path.
signal CPUdone_seen, SUBdone_seen : std_logic;
signal CPUdone_sync, SUBdone_sync : std_logic_vector(1 downto 0);
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
type cpu_words_t is array(0 to 3) of std_logic_vector(15 downto 0);
signal cpu_read_words, cpu_write_words : cpu_words_t;
signal cpu_read_crossing, sub_read_crossing : cpu_words_t;
signal cpu_write_source, cpu_write_crossing, cpu_write_memory : std_logic_vector(ADRWIDTH+152 downto 0);
signal cpu_address : std_logic_vector(ADRWIDTH-1 downto 0);
signal cpu_bank, cpu_bytes : std_logic_vector(1 downto 0);
signal cpu_planes : std_logic_vector(3 downto 0);
signal sub_read_words, sub_write_words : cpu_words_t;
signal sub_write_source, sub_write_crossing, sub_write_memory : std_logic_vector(ADRWIDTH+87 downto 0);
signal sub_address : std_logic_vector(ADRWIDTH-1 downto 0);
signal sub_bank, sub_bytes : std_logic_vector(1 downto 0);
signal sub_planes : std_logic_vector(3 downto 0);

signal fde_request_source, fde_request_crossing, fde_request_memory : std_logic_vector(ADRWIDTH+17 downto 0);
signal fec_request_source, fec_request_crossing, fec_request_memory : std_logic_vector(ADRWIDTH+17 downto 0);
signal fde_address, fec_address : std_logic_vector(ADRWIDTH+1 downto 0);
signal fde_read_data, fec_read_data : std_logic_vector(15 downto 0);
signal fde_read_crossing, fec_read_crossing : std_logic_vector(15 downto 0);
signal fde_write_data, fec_write_data : std_logic_vector(15 downto 0);
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
signal	FECJOB,nFECJOB,lFECJOB	:job_t;
signal	CPUREQ	:std_logic;
signal	SUBREQ	:std_logic;
-- One outstanding graphics transfer. Request and completion are toggles,
-- so a pulse or the previous acknowledgement cannot be sampled as a new job.
signal VIDREQ, VIDbusy : std_logic;
signal VIDdone_sync : std_logic_vector(1 downto 0);
attribute preserve : boolean;
attribute preserve of lCPUREQ, lSUBREQ, CPUdone_sync, SUBdone_sync : signal is true;
attribute preserve of cpu_write_source, cpu_write_memory : signal is true;
attribute preserve of sub_write_source, sub_write_memory : signal is true;
attribute preserve of fde_request_source, fde_request_memory, fec_request_source, fec_request_memory : signal is true;
attribute preserve of lVIDREQ, VIDdone_sync : signal is true;
attribute altera_attribute : string;
attribute altera_attribute of lCPUREQ, lSUBREQ, CPUdone_sync, SUBdone_sync : signal is
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
attribute altera_attribute of lVIDREQ, VIDdone_sync : signal is
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
-- A completion toggle identifies exactly one outstanding floppy transfer.
signal FDEREQ, FECREQ, FDEbusy, FECbusy, FDEaccept, FECaccept : std_logic;
signal FDEdone_sync, FECdone_sync : std_logic_vector(1 downto 0);
attribute preserve of lFDEREQ, lFECREQ, FDEdone_sync, FECdone_sync : signal is true;
attribute altera_attribute of lFDEREQ, lFECREQ, FDEdone_sync, FECdone_sync : signal is
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";

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

    FDEWAIT <= FDEbusy;
    FECWAIT <= FECbusy;
    FDEaccept <= '1' when FDEbusy='0' and
        ((FDEWR='1' and (lfdestb='0' or lFDEADR/=FDEADR or lFDEJOB/=JOB_WR)) or
         (FDEWR='0' and FDERD='1' and (lfdestb='0' or lFDEADR/=FDEADR or lFDEJOB/=JOB_RD))) else '0';
    FECaccept <= '1' when FECbusy='0' and
        ((FECWR='1' and (lfecstb='0' or lFECADR/=FECADR or lFECJOB/=JOB_WR)) or
         (FECWR='0' and FECRD='1' and (lfecstb='0' or lFECADR/=FECADR or lFECJOB/=JOB_RD))) else '0';

    fde_request_crossing <= fde_request_source; -- FDE_REQUEST_BUNDLE_TRANSPORT
    fec_request_crossing <= fec_request_source; -- FEC_REQUEST_BUNDLE_TRANSPORT
    fde_read_crossing <= fde_read_data; -- FDE_READ_BUNDLE_TRANSPORT
    fec_read_crossing <= fec_read_data; -- FEC_READ_BUNDLE_TRANSPORT
    floppy_bundle : if FLOPPY_REQUEST_BUNDLE generate
        -- These are the same acceptance conditions as FDEREQ/FECREQ.
        -- The held address/data reach memory with the corresponding JOB.
        process(FDECLK) begin
            if rising_edge(FDECLK) then
                if FDEaccept='1' then
                    fde_request_source <= FDEADR & FDEWDAT;
                end if;
            end if;
        end process;
        process(FECCLK) begin
            if rising_edge(FECCLK) then
                if FECaccept='1' then
                    fec_request_source <= FECADR & FECWDAT;
                end if;
            end if;
        end process;
        process(memclk) begin
            if rising_edge(memclk) then
                if lFDEREQ(2)/=lFDEREQ(1) then -- FDE_REQUEST_BUNDLE_ADMISSION
                    fde_request_memory <= fde_request_crossing;
                end if;
                if lFECREQ(2)/=lFECREQ(1) then -- FEC_REQUEST_BUNDLE_ADMISSION
                    fec_request_memory <= fec_request_crossing;
                end if;
            end if;
        end process;
        process(FDECLK,rstn) begin
            if rstn='0' then
                FDERDAT <= (others=>'0');
            elsif rising_edge(FDECLK) then
                if FDEbusy='1' and FDEdone_sync(1)=FDEREQ then -- FDE_READ_COMPLETION_CAPTURE
                    FDERDAT <= fde_read_crossing;
                end if;
            end if;
        end process;
        process(FECCLK,rstn) begin
            if rstn='0' then
                FECRDAT <= (others=>'0');
            elsif rising_edge(FECCLK) then
                if FECbusy='1' and FECdone_sync(1)=FECREQ then -- FEC_READ_COMPLETION_CAPTURE
                    FECRDAT <= fec_read_crossing;
                end if;
            end if;
        end process;
        fde_address <= fde_request_memory(ADRWIDTH+17 downto 16);
        fec_address <= fec_request_memory(ADRWIDTH+17 downto 16);
        fde_write_data <= fde_request_memory(15 downto 0);
        fec_write_data <= fec_request_memory(15 downto 0);
    end generate;
    legacy_floppy_request : if not FLOPPY_REQUEST_BUNDLE generate
        FDERDAT <= fde_read_data; FECRDAT <= fec_read_data;
        fde_address <= FDEADR; fec_address <= FECADR;
        fde_write_data <= FDEWDAT; fec_write_data <= FECWDAT;
    end generate;

    cpu_read_crossing <= cpu_read_words; -- CPU_READ_BUNDLE_TRANSPORT
    sub_read_crossing <= sub_read_words; -- SUB_READ_BUNDLE_TRANSPORT

    sub_write_crossing <= sub_write_source; -- SUB_WRITE_BUNDLE_TRANSPORT
    sub_bundle : if SUB_WRITE_BUNDLE generate
        -- The GDC drawing port has its own request/ACK handshake. Capture
        -- the static GRCG set/preserve operands at the request source, then
        -- admit them with SUBJOB after its three memory-clock stages.
        process(SUBCLK) begin
            if rising_edge(SUBCLK) then
                if SUBREQS='1' and lsubstb='0' then
                    sub_write_source <= SUBADR & SUBBNK & SUBBSEL & SUBPSEL &
                        SUBPRESERVE & SUBWDAT3 & SUBWDAT2 & SUBWDAT1 & SUBWDAT0;
                end if;
            end if;
        end process;
        process(memclk) begin
            if rising_edge(memclk) then
                if lSUBREQ(2)/=lSUBREQ(1) then -- SUB_WRITE_BUNDLE_ADMISSION
                    sub_write_memory <= sub_write_crossing;
                end if;
            end if;
        end process;
        sub_address <= sub_write_memory(ADRWIDTH+87 downto 88);
        sub_bank <= sub_write_memory(87 downto 86);
        sub_bytes <= sub_write_memory(85 downto 84);
        sub_planes <= sub_write_memory(83 downto 80);
        planes : for i in 0 to 3 generate
            sub_write_words(i) <= sub_write_memory(i*16+15 downto i*16) or
                (sub_read_words(i) and sub_write_memory(79 downto 64));
        end generate;
        process(SUBCLK,rstn) begin
            if rstn='0' then
                SUBRDAT0 <= (others=>'0'); SUBRDAT1 <= (others=>'0');
                SUBRDAT2 <= (others=>'0'); SUBRDAT3 <= (others=>'0');
            elsif rising_edge(SUBCLK) then
                if SUBdone_sync(1)/=SUBdone_seen then -- SUB_READ_COMPLETION_CAPTURE
                    SUBRDAT0 <= sub_read_crossing(0);
                    SUBRDAT1 <= sub_read_crossing(1);
                    SUBRDAT2 <= sub_read_crossing(2);
                    SUBRDAT3 <= sub_read_crossing(3);
                end if;
            end if;
        end process;
    end generate;
    legacy_sub_write : if not SUB_WRITE_BUNDLE generate
        sub_address <= SUBADR; sub_bank <= SUBBNK;
        sub_bytes <= SUBBSEL; sub_planes <= SUBPSEL;
        sub_write_words <= (SUBWDAT0, SUBWDAT1, SUBWDAT2, SUBWDAT3);
        SUBRDAT0 <= sub_read_words(0); SUBRDAT1 <= sub_read_words(1);
        SUBRDAT2 <= sub_read_words(2); SUBRDAT3 <= sub_read_words(3);
    end generate;

    assert not CPU_AFFINE_RMW or CPU_WRITE_BUNDLE
        report "Affine RMW requires the held CPU request bundle" severity failure;
    cpu_write_crossing <= cpu_write_source; -- CPU_WRITE_BUNDLE_TRANSPORT
    write_bundle : if CPU_WRITE_BUNDLE generate
        -- A change in the held completion toggle captures read data and
        -- asserts CPUACKb together after two synchronization stages. The bridge
        -- consumes both on the following CPU edge. RMW uses fresh
        -- memory-domain words internally, not these CPU-visible registers.
        process(CPUCLK,rstn) begin
            if rstn='0' then
                CPURDAT0 <= (others=>'0'); CPURDAT1 <= (others=>'0');
                CPURDAT2 <= (others=>'0'); CPURDAT3 <= (others=>'0');
            elsif rising_edge(CPUCLK) then
                if CPUdone_sync(1)/=CPUdone_seen then -- CPU_READ_COMPLETION_CAPTURE
                    CPURDAT0 <= cpu_read_crossing(0);
                    CPURDAT1 <= cpu_read_crossing(1);
                    CPURDAT2 <= cpu_read_crossing(2);
                    CPURDAT3 <= cpu_read_crossing(3);
                end if;
            end if;
        end process;
        process(CPUCLK) begin
            if rising_edge(CPUCLK) then
                if (CPUWR1 or CPUWR4 or CPURD1 or CPURD4 or CPURMW1 or CPURMW4)='1'
                   and (lcpustb='0' or lCPUADR/=CPUADR) then
                    cpu_write_source(ADRWIDTH+87 downto 0) <= CPUADR & CPUBNK & CPUBSEL & CPUPSEL &
                        CPUPRESERVE & CPUWDAT3 & CPUWDAT2 & CPUWDAT1 & CPUWDAT0;
                    if CPU_AFFINE_RMW then
                        cpu_write_source(ADRWIDTH+152) <= CPUAFFINE and CPURMW4;
                        cpu_write_source(ADRWIDTH+151 downto ADRWIDTH+88) <= CPUXORMASK;
                    else
                        cpu_write_source(ADRWIDTH+152 downto ADRWIDTH+88) <= (others=>'0');
                    end if;
                end if;
            end if;
        end process;
        process(memclk) begin
            if rising_edge(memclk) then
                -- Same admission edge as CPUJOB. The source was captured
                -- before the synchronized request toggle reaches admission.
                if lCPUREQ(2)/=lCPUREQ(1) then -- CPU_WRITE_BUNDLE_ADMISSION
                    cpu_write_memory <= cpu_write_crossing;
                end if;
            end if;
        end process;
        cpu_address <= cpu_write_memory(ADRWIDTH+87 downto 88);
        cpu_bank <= cpu_write_memory(87 downto 86);
        cpu_bytes <= cpu_write_memory(85 downto 84);
        cpu_planes <= cpu_write_memory(83 downto 80);
        planes : for i in 0 to 3 generate
            -- Merge fresh memory-domain destination data; no extra
            -- memory command, CPU round trip or handshake is needed.
            cpu_write_words(i) <=
                cpu_write_memory(i*16+15 downto i*16) xor
                (cpu_read_words(i) and cpu_write_memory(ADRWIDTH+103+i*16 downto ADRWIDTH+88+i*16))
                when CPU_AFFINE_RMW and cpu_write_memory(ADRWIDTH+152)='1' else
                cpu_write_memory(i*16+15 downto i*16) or
                (cpu_read_words(i) and cpu_write_memory(79 downto 64));
        end generate;
    end generate;
    legacy_cpu_write : if not CPU_WRITE_BUNDLE generate
        cpu_address <= lCPUADR; cpu_bank <= lCPUBNK;
        cpu_bytes <= lCPUBSEL; cpu_planes <= lCPUPSEL;
        cpu_write_words <= (CPUWDAT0, CPUWDAT1, CPUWDAT2, CPUWDAT3);
        -- Legacy GRCG computes its RMW result through these live outputs.
        CPURDAT0 <= cpu_read_words(0);
        CPURDAT1 <= cpu_read_words(1);
        CPURDAT2 <= cpu_read_words(2);
        CPURDAT3 <= cpu_read_words(3);
    end generate;

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
			fdeend<='0';
			fecend<='0';
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
			if(lCPUREQ(2)/=lCPUREQ(1))then
				CPUJOB<=nCPUJOB;
			end if;
			if(lSUBREQ(2)/=lSUBREQ(1))then
				SUBJOB<=nSUBJOB;
			end if;
			if(lVIDREQ(2)/=lVIDREQ(1))then
				VIDJOB<=JOB_RD;
			end if;
			if(lFDEREQ(2)/=lFDEREQ(1))then
				FDEJOB<=nFDEJOB;
			end if;
			if(lFECREQ(2)/=lFECREQ(1))then
				FECJOB<=nFECJOB;
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<=cpu_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<="000" & cpu_address(9 downto 0);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<=cpu_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<="000" & cpu_address(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>	--DQ
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<=cpu_address(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not cpu_bytes(1);
						MEMLDQ		<=not cpu_bytes(0);
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not cpu_bytes(1) & not cpu_bytes(0);
						MEMADR(10 downto 0)	<='0' & cpu_address(9 downto 0);
						MEMDAT<=cpu_write_words(0);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<=cpu_address(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						CPUJOB<=JOB_NOP;
					when 2 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (cpu_planes(0) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(0) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(0) and cpu_bytes(1)) & not (cpu_planes(0) and cpu_bytes(0));
						MEMADR(10 downto 0)	<='0' & cpu_address(9 downto 2) & "00";
						MEMDAT<=cpu_write_words(0);
						MEMDATOE	<='1';
					when 3 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (cpu_planes(1) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(1) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(1) and cpu_bytes(1)) & not (cpu_planes(1) and cpu_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT<=cpu_write_words(1);
						MEMDATOE	<='1';
					when 4 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (cpu_planes(2) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(2) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(2) and cpu_bytes(1)) & not (cpu_planes(2) and cpu_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT<=cpu_write_words(2);
						MEMDATOE	<='1';
					when 5 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (cpu_planes(3) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(3) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(3) and cpu_bytes(1)) & not (cpu_planes(3) and cpu_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT<=cpu_write_words(3);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<=cpu_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<="000" & cpu_address(9 downto 0);
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN(Hi-Z)
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not cpu_bytes(1);
						MEMLDQ		<=not cpu_bytes(0);
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not cpu_bytes(1) & not cpu_bytes(0);
						MEMADR(10 downto 0)	<='0' & cpu_address(9 downto 0);
						MEMDAT<=cpu_write_words(0);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<=cpu_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR		<="000" & cpu_address(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
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
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (cpu_planes(0) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(0) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(0) and cpu_bytes(1)) & not (cpu_planes(0) and cpu_bytes(0));
						MEMADR(10 downto 0)	<='0' & cpu_address(9 downto 2) & "00"; -- CPU_RMW4_ALIGN
						MEMDAT<=cpu_write_words(0);
						MEMDATOE	<='1';
					when 9 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (cpu_planes(1) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(1) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(1) and cpu_bytes(1)) & not (cpu_planes(1) and cpu_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT<=cpu_write_words(1);
						MEMDATOE	<='1';
					when 10 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (cpu_planes(2) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(2) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(2) and cpu_bytes(1)) & not (cpu_planes(2) and cpu_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT<=cpu_write_words(2);
						MEMDATOE	<='1';
					when 11 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (cpu_planes(3) and cpu_bytes(1));
						MEMLDQ		<=not (cpu_planes(3) and cpu_bytes(0));
						MEMBA1		<=cpu_bank(1);
						MEMBA0		<=cpu_bank(0);
						MEMADR(12 downto 11)	<=not (cpu_planes(3) and cpu_bytes(1)) & not (cpu_planes(3) and cpu_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT<=cpu_write_words(3);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=sub_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<="000" & sub_address(9 downto 0);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=sub_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<="000" & sub_address(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>	--DQ
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=sub_address(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not sub_bytes(1);
						MEMLDQ		<=not sub_bytes(0);
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not sub_bytes(1) & not sub_bytes(0);
						MEMADR(10 downto 0)	<='0' & sub_address(9 downto 0);
						MEMDAT		<=sub_write_words(0);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=sub_address(ADRWIDTH-1 downto ADRWIDTH-13);
						MEMDATOE	<='0';
						SUBJOB<=JOB_NOP;
					when 2 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (sub_planes(0) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(0) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(0) and sub_bytes(1)) & not (sub_planes(0) and sub_bytes(0));
						MEMADR(10 downto 0)	<='0' & sub_address(9 downto 2) & "00";
						MEMDAT		<=sub_write_words(0);
						MEMDATOE	<='1';
					when 3 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (sub_planes(1) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(1) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(1) and sub_bytes(1)) & not (sub_planes(1) and sub_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=sub_write_words(1);
						MEMDATOE	<='1';
					when 4 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (sub_planes(2) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(2) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(2) and sub_bytes(1)) & not (sub_planes(2) and sub_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=sub_write_words(2);
						MEMDATOE	<='1';
					when 5 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (sub_planes(3) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(3) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(3) and sub_bytes(1)) & not (sub_planes(3) and sub_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=sub_write_words(3);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=sub_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<="000" & sub_address(9 downto 0);
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN(Hi-Z)
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='1';
						MEMLDQ		<='1';
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<="11";
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDATOE	<='0';
					when 8 =>		--write command & send word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not sub_bytes(1);
						MEMLDQ		<=not sub_bytes(0);
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not sub_bytes(1) & not sub_bytes(0);
						MEMADR(10 downto 0)	<='0' & sub_address(9 downto 0);
						MEMDAT		<=sub_write_words(0);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=sub_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<="000" & sub_address(9 downto 2) & "00";
						MEMDATOE	<='0';
					when 3 | 4 | 5 =>		--DQN
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<='0';
						MEMLDQ		<='0';
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR		<=(others=>'0');
						MEMDATOE	<='0';
					when 11 =>		--write command & send 1st word
						MEMCKE		<='1';
						MEMCS_N		<='0';
						MEMRAS_N	<='1';
						MEMCAS_N	<='0';
						MEMWE_N		<='0';
						MEMUDQ		<=not (sub_planes(0) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(0) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(0) and sub_bytes(1)) & not (sub_planes(0) and sub_bytes(0));
						MEMADR(10 downto 0)	<='0' & sub_address(9 downto 2) & "00"; -- SUB_RMW4_ALIGN
						MEMDAT		<=sub_write_words(0);
						MEMDATOE	<='1';
					when 12 =>		--2nd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (sub_planes(1) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(1) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(1) and sub_bytes(1)) & not (sub_planes(1) and sub_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=sub_write_words(1);
						MEMDATOE	<='1';
					when 13 =>		--3rd word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (sub_planes(2) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(2) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(2) and sub_bytes(1)) & not (sub_planes(2) and sub_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=sub_write_words(2);
						MEMDATOE	<='1';
					when 14 =>		--4th word
						MEMCKE		<='1';
						MEMCS_N		<='1';
						MEMRAS_N	<='1';
						MEMCAS_N	<='1';
						MEMWE_N		<='1';
						MEMUDQ		<=not (sub_planes(3) and sub_bytes(1));
						MEMLDQ		<=not (sub_planes(3) and sub_bytes(0));
						MEMBA1		<=sub_bank(1);
						MEMBA0		<=sub_bank(0);
						MEMADR(12 downto 11)	<=not (sub_planes(3) and sub_bytes(1)) & not (sub_planes(3) and sub_bytes(0));
						MEMADR(10 downto 0)	<=(others=>'0');
						MEMDAT		<=sub_write_words(3);
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
						MEMBA1		<=fde_address(ADRWIDTH+1);
						MEMBA0		<=fde_address(ADRWIDTH);
						MEMADR		<=fde_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=fde_address(ADRWIDTH+1);
						MEMBA0		<=fde_address(ADRWIDTH);
						MEMADR		<="000" & fde_address(9 downto 0);
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
						MEMBA1		<=fde_address(ADRWIDTH+1);
						MEMBA0		<=fde_address(ADRWIDTH);
						MEMADR		<=fde_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=fde_address(ADRWIDTH+1);
						MEMBA0		<=fde_address(ADRWIDTH);
						MEMADR		<="000" & fde_address(9 downto 0);
						MEMDAT		<=fde_write_data;
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
						MEMBA1		<=fec_address(ADRWIDTH+1);
						MEMBA0		<=fec_address(ADRWIDTH);
						MEMADR		<=fec_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=fec_address(ADRWIDTH+1);
						MEMBA0		<=fec_address(ADRWIDTH);
						MEMADR		<="000" & fec_address(9 downto 0);
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
						MEMBA1		<=fec_address(ADRWIDTH+1);
						MEMBA0		<=fec_address(ADRWIDTH);
						MEMADR		<=fec_address(ADRWIDTH-1 downto ADRWIDTH-13);
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
						MEMBA1		<=fec_address(ADRWIDTH+1);
						MEMBA0		<=fec_address(ADRWIDTH);
						MEMADR		<="000" & fec_address(9 downto 0);
						MEMDAT		<=fec_write_data;
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
						cpuend<=not cpuend;
					when ST_SUBREAD | ST_SUBREAD4 | ST_SUBWRITE | ST_SUBWRITE4 | ST_SUBRMW | ST_SUBRMW4 =>
						subend<=not subend;
					when ST_VIDREAD =>
						vidend<=lVIDREQ(2);
					when ST_FDEREAD | ST_FDEWRITE =>
						fdeend<=lFDEREQ(2);
					when ST_FECREAD | ST_FECWRITE =>
						fecend<=lFECREQ(2);
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
			cpu_read_words(0)	<=(others=>'0');
			cpu_read_words(1)	<=(others=>'0');
			cpu_read_words(2)	<=(others=>'0');
			cpu_read_words(3)	<=(others=>'0');
			sub_read_words(0)	<=(others=>'0');
			sub_read_words(1)	<=(others=>'0');
			sub_read_words(2)	<=(others=>'0');
			sub_read_words(3)	<=(others=>'0');
			VIDDAT0		<=(others=>'0');
			VIDDAT1		<=(others=>'0');
			VIDDAT2		<=(others=>'0');
			VIDDAT3		<=(others=>'0');
			fde_read_data		<=(others=>'0');
			fec_read_data		<=(others=>'0');
			lSTATE		<=ST_REFRESH;
			lclkcount	<=clkcount;
		elsif(memclk' event and memclk='1')then
			case lSTATE is
			when ST_READ | ST_RMW =>
				if(lclkcount=6)then
					cpu_read_words(0)<=SMEMDAT;
				end if;
			when ST_READ4 | ST_RMW4 =>
				case lclkcount is
				when 6 =>
					cpu_read_words(0)<=SMEMDAT;
				when 7 =>
					cpu_read_words(1)<=SMEMDAT;
				when 8 =>
					cpu_read_words(2)<=SMEMDAT;
				when 9 =>
					cpu_read_words(3)<=SMEMDAT;
				when others =>
				end case;
			when ST_SUBREAD |ST_SUBRMW =>
				if(lclkcount=6)then
					sub_read_words(0)<=SMEMDAT;
				end if;
			when ST_SUBREAD4 | ST_SUBRMW4 =>
				case lclkcount is
				when 6 =>
					sub_read_words(0)<=SMEMDAT;
				when 7 =>
					sub_read_words(1)<=SMEMDAT;
				when 8 =>
					sub_read_words(2)<=SMEMDAT;
				when 9 =>
					sub_read_words(3)<=SMEMDAT;
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
					fde_read_data<=SMEMDAT;
				end if;
			when ST_FECREAD =>
				if(lclkcount=6)then
					fec_read_data<=SMEMDAT;
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
            CPUdone_seen<='0';
            CPUdone_sync<=(others=>'0');
			CPUREQ<='0';
		elsif(CPUCLK' event and CPUCLK='1')then
            CPUdone_sync<=CPUdone_sync(0) & cpuend;
            -- Capture request metadata in its source clock domain before the
            -- existing request synchronizer admits the job to SDRAM. Avoid
            -- live CPU/DMA address-decode paths feeding the 100 MHz pins.
            -- The optional write bundle is captured on this same edge; its
            -- preserve mask is applied to fresh RMW data in the memory domain.
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
					CPUREQ<=not CPUREQ;
				end if;
			elsif(CPUWR4='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_WR4;
					CPUREQ<=not CPUREQ;
				end if;
			elsif(CPURD1='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RD;
					CPUREQ<=not CPUREQ;
				end if;
			elsif(CPURD4='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RD4;
					CPUREQ<=not CPUREQ;
				end if;
			elsif(CPURMW1='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RMW;
					CPUREQ<=not CPUREQ;
				end if;
			elsif(CPURMW4='1')then
				lcpustb<='1';
				if(lcpustb='0' or lCPUADR/=CPUADR)then
					lCPUADR<=CPUADR;
					nCPUJOB<=JOB_RMW4;
					CPUREQ<=not CPUREQ;
				end if;
			else
				lcpustb<='0';
			end if;

            CPUACKb<=CPUdone_sync(1) xor CPUdone_seen;
            CPUdone_seen<=CPUdone_sync(1);
		end if;
	end process;
	
	SUBREQS<=SUBWR1 or SUBWR4 or SUBRD1 or SUBRD4 or SUBRMW1 or SUBRMW4;
	
	process(SUBCLK,rstn)begin
		if(rstn='0')then
			nSUBJOB<=JOB_NOP;
			lsubstb<='0';
			SUBACKb<='0';
            SUBdone_seen<='0';
            SUBdone_sync<=(others=>'0');
			SUBREQ<='0';
		elsif(SUBCLK' event and SUBCLK='1')then
            SUBdone_sync<=SUBdone_sync(0) & subend;
--			nSUBJOB<=JOB_NOP;
			if(SUBWR1='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_WR;
					SUBREQ<=not SUBREQ;
				end if;
			elsif(SUBWR4='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_WR4;
					SUBREQ<=not SUBREQ;
				end if;
			elsif(SUBRD1='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RD;
					SUBREQ<=not SUBREQ;
				end if;
			elsif(SUBRD4='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RD4;
					SUBREQ<=not SUBREQ;
				end if;
			elsif(SUBRMW1='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RMW;
					SUBREQ<=not SUBREQ;
				end if;
			elsif(SUBRMW4='1')then
				lsubstb<='1';
				if(lsubstb='0')then
					nSUBJOB<=JOB_RMW4;
					SUBREQ<=not SUBREQ;
				end if;
			else
				lsubstb<='0';
			end if;

            SUBdone_seen<=SUBdone_sync(1);
            if SUBdone_sync(1)/=SUBdone_seen then
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

    process(FDECLK,rstn) begin
        if rstn='0' then
            lFDEADR<=(others=>'0'); nFDEJOB<=JOB_NOP; lFDEJOB<=JOB_NOP;
            lfdestb<='0'; FDEACKb<='0'; FDEREQ<='0'; FDEbusy<='0';
            FDEdone_sync<=(others=>'0');
        elsif rising_edge(FDECLK) then
            FDEdone_sync<=FDEdone_sync(0) & fdeend;
            lfdestb<=FDEWR or FDERD;
            FDEACKb<='0';
            if FDEaccept='1' then
                lFDEADR<=FDEADR;
                if FDEWR='1' then
                    nFDEJOB<=JOB_WR; lFDEJOB<=JOB_WR;
                else
                    nFDEJOB<=JOB_RD; lFDEJOB<=JOB_RD;
                end if;
                FDEREQ<=not FDEREQ;
                FDEbusy<='1';
            elsif FDEbusy='1' and FDEdone_sync(1)=FDEREQ then
                -- Capture returned data on this same completion edge.
                FDEACKb<='1';
                FDEbusy<='0';
            end if;
        end if;
    end process;

    process(FECCLK,rstn) begin
        if rstn='0' then
            lFECADR<=(others=>'0'); nFECJOB<=JOB_NOP; lFECJOB<=JOB_NOP;
            lfecstb<='0'; FECACKb<='0'; FECREQ<='0'; FECbusy<='0';
            FECdone_sync<=(others=>'0');
        elsif rising_edge(FECCLK) then
            FECdone_sync<=FECdone_sync(0) & fecend;
            lfecstb<=FECWR or FECRD;
            FECACKb<='0';
            if FECaccept='1' then
                lFECADR<=FECADR;
                if FECWR='1' then
                    nFECJOB<=JOB_WR; lFECJOB<=JOB_WR;
                else
                    nFECJOB<=JOB_RD; lFECJOB<=JOB_RD;
                end if;
                FECREQ<=not FECREQ;
                FECbusy<='1';
            elsif FECbusy='1' and FECdone_sync(1)=FECREQ then
                -- Capture returned data on this same completion edge.
                FECACKb<='1';
                FECbusy<='0';
            end if;
        end if;
    end process;

	CPUACK<=CPUACKb;
	SUBACK<=SUBACKb;
	VIDACK<=VIDACKb;
--	FDEACK<=FDEACKb;
--	FECACK<=FECACKb;

end MAIN;
