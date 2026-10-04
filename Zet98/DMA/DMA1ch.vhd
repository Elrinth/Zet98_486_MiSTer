LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity DMA1ch is
port(
	PADDR	:in std_logic;
	PRD		:in std_logic;
	PWR		:in std_logic;
	PRDATA	:out std_logic_vector(7 downto 0);
	PWDATA	:in std_logic_vector(7 downto 0);
	PDOE	:out std_logic;
	
	CONTEN	:in std_logic;
	CHEN	:in std_logic;
	DIRMODE	:in std_logic_vector(1 downto 0);
	AUTOINI	:in std_logic;
	DEC_INCn:in std_logic;
	OPMODE	:in std_logic_vector(1 downto 0);
	
	DREQ	:in std_logic;
	BUSREQ	:out std_logic;
	BUSACK	:in std_logic;
	DACK	:out std_logic;
	DADDR	:out std_logic_vector(15 downto 0);
	DAOE	:out std_logic;
	MEMRD	:out std_logic;
	MEMWR	:out std_logic;
	IORD	:out std_logic;
	IOWR	:out std_logic;
	IOWAIT	:in std_logic;
	IOACK	:in std_logic;
	MEMACK	:in std_logic;
	TC		:out std_logic;
	ACARRY	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end DMA1ch;

architecture rtl of DMA1ch is
signal	CURADDR		:std_logic_vector(15 downto 0);
signal	BASEADDR	:std_logic_vector(15 downto 0);
signal	CURCOUNT		:std_logic_vector(15 downto 0);
signal	BASECOUNT	:std_logic_vector(15 downto 0);
signal	ADDRINC		:std_logic;
type state_t is(
	st_IDLE,
	st_WAITBUS,
	st_TRANS0,
	st_TRANS1,
	st_TRANS2,
	st_TRANS3,
	st_TRANS4,
	st_TRANS5,
	st_TRANS6,
	st_END,
	st_NEXT
);
signal	state	:state_t;
signal	PDATH_Ln	:std_logic;
begin
	process(clk,rstn)begin
		if(rstn='0')then
			CURADDR<=(others=>'0');
			BASEADDR<=(others=>'0');
			CURCOUNT<=(others=>'0');
			BASECOUNT<=(others=>'0');
			TC<='0';
			ACARRY<='0';
		elsif(clk' event and clk='1')then
			TC<='0';
			ACARRY<='0';
			if(PWR='1')then
				if(PADDR='0')then
					if(PDATH_Ln='0')then
						CURADDR(7 downto 0)<=PWDATA;
						BASEADDR(7 downto 0)<=PWDATA;
					else
						CURADDR(15 downto 8)<=PWDATA;
						BASEADDR(15 downto 8)<=PWDATA;
					end if;
				else
					if(PDATH_Ln='0')then
						CURCOUNT(7 downto 0)<=PWDATA;
						BASECOUNT(7 downto 0)<=PWDATA;
					else
						CURCOUNT(15 downto 8)<=PWDATA;
						BASECOUNT(15 downto 8)<=PWDATA;
					end if;
				end if;
			end if;
			if(ADDRINC='1')then
				if(DEC_INCn='0')then
					if(CURADDR=x"ffff")then
						ACARRY<='1';
					end if;
					CURADDR<=CURADDR+x"0001";
				else
					if(CURADDR=x"0000")then
						ACARRY<='1';
					end if;
					CURADDR<=CURADDR-x"0001";
				end if;
				if(CURCOUNT=x"0000")then
					TC<='1';
					if(AUTOINI='1')then
						CURCOUNT<=BASECOUNT;
						CURADDR<=BASEADDR;
					else
						-- Monitors use the residual count to copy DMA bounce buffers.
						-- A completed non-auto-init transfer must read back FFFFh.
						CURCOUNT<=x"ffff";
					end if;
				else
					CURCOUNT<=CURCOUNT-1;
				end if;
			end if;
			
		end if;
	end process;
	
	process(clk,rstn)
	variable lRD,lWR	:std_logic;
	begin
		if(rstn='0')then
			PDATH_Ln<='0';
			lRD:='0';
			lWR:='0';
		elsif(clk' event and clk='1')then
			if(CONTEN='0')then
				PDATH_Ln<='0';
			elsif(lRD='1' and PRD='0')then
				PDATH_Ln<=not PDATH_Ln;
			elsif(lWR='1' and PWR='0')then
				PDATH_Ln<=not PDATH_Ln;
			end if;
			lRD:=PRD;
			lWR:=PWR;
		end if;
	end process;
	
	PRDATA<=	CURADDR(7 downto 0)		when PADDR='0' and PDATH_Ln='0' else
				CURADDR(15 downto 8)	when PADDR='0' and PDATH_Ln='1' else
				CURCOUNT( 7 downto 0)	when PADDR='1' and PDATH_Ln='0' else
				CURCOUNT(15 downto 8)	when PADDR='1' and PDATH_Ln='1' else
				(others=>'0');
	PDOE<=PRD;
	
	process(clk,rstn)begin
		if(rstn='0')then
			state<=st_IDLE;
			BUSREQ<='0';
			DACK<='0';
			MEMRD<='0';
			MEMWR<='0';
			IORD<='0';
			IOWR<='0';
			DAOE<='0';
			ADDRINC<='0';
		elsif(clk' event and clk='1')then
			ADDRINC<='0';
			case state is
			when st_IDLE =>
				if(CHEN='1')then
					if(DREQ='1')then
						BUSREQ<='1';
						state<=st_WAITBUS;
					end if;
				end if;
			when st_WAITBUS =>
				if(BUSACK='1')then
					DAOE<='1';
					if(DIRMODE="00" or DIRMODE="10")then
						MEMRD<='1';
						state<=st_TRANS1;
					elsif(DIRMODE="01")then
						DACK<='1';
						IORD<='1';
						state<=st_TRANS0;
					end if;
				end if;
			when st_TRANS0 =>
				state<=st_TRANS1;
			when st_TRANS1 =>
				if(DIRMODE="00" or DIRMODE="10")then
					if(MEMACK='1')then
						DACK<='1';
						IOWR<='1';
						state<=st_TRANS2;
					end if;
				else
					if(IOWAIT='0')then
						MEMWR<='1';
						state<=st_TRANS3;
					end if;
				end if;
			when st_TRANS2 =>
				state<=st_TRANS3;
			when st_TRANS3 =>
				if(DIRMODE="00" or DIRMODE="10")then
					if(IOWAIT='0')then
						DACK<='0';
						IOWR<='0';
						MEMRD<='0';
						ADDRINC<='1';
						if(OPMODE="00" and CURCOUNT/=x"0000")then
							state<=st_TRANS6;
						elsif(OPMODE="10" and CURCOUNT/=x"0000")then
							state<=st_TRANS4;
						else
							BUSREQ<='0';
							DAOE<='0';
							state<=st_TRANS5;
						end if;
					end if;
				else
					if(MEMACK='1')then
						DACK<='0';
						IORD<='0';
						MEMWR<='0';
						ADDRINC<='1';
						if(OPMODE="00" and CURCOUNT/=x"0000")then
							state<=st_TRANS6;
						elsif(OPMODE="10" and CURCOUNT/=x"0000")then
							state<=st_TRANS4;
						else
							DAOE<='0';
							state<=st_TRANS5;
						end if;
					end if;
				end if;
			when st_TRANS4 =>
				if(MEMACK='0')then
					state<=st_WAITBUS;
				end if;
			when st_TRANS5 =>
				if(MEMACK='0')then
					state<=st_END;
				end if;
			when st_TRANS6 =>
				if(MEMACK='0')then
					state<=st_NEXT;
				end if;
			when st_NEXT =>
				if(DREQ='1')then
					state<=st_WAITBUS;
				else
					DAOE<='0';
					state<=st_END;
				end if;
			when st_END =>
				if(IOACK='0' and MEMACK='0')then
					BUSREQ<='0';
					state<=st_IDLE;
				end if;
			when others =>
				DAOE<='0';
				state<=st_IDLE;
			end case;
		end if;
	end process;
	DADDR<=CURADDR;
	
end rtl;					
						
						
			
	
	