LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity DMA8237 is
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
end DMA8237;

architecture rtl of DMA8237 is
signal	M2Men		:std_logic;
signal	CH0AHOLD	:std_logic;
signal	CONTEN		:std_logic;
signal	BYTE_CLEAR	:std_logic;
signal	COMPRESS	:std_logic;
signal	ROTPRI		:std_logic;
signal	CURPRI		:integer range 0 to 3;
signal	ACTCH		:integer range 0 to 4;
signal	WREXT		:std_logic;
signal	DRQlog		:std_logic;
signal	DACKlog		:std_logic;
signal	DRQX		:std_logic_vector(3 downto 0);
signal	DRQV		:std_logic_vector(3 downto 0);
signal	DACKV		:std_logic_vector(3 downto 0);

signal	TCb			:std_logic_vector(3 downto 0);
signal	TClat		:std_logic_vector(3 downto 0);

signal	CH0TMODE	:std_logic_vector(1 downto 0);
signal	CH1TMODE	:std_logic_vector(1 downto 0);
signal	CH2TMODE	:std_logic_vector(1 downto 0);
signal	CH3TMODE	:std_logic_vector(1 downto 0);

signal	CHAUTOINI	:std_logic_vector(3 downto 0);

signal	CHADEC_INCn	:std_logic_vector(3 downto 0);

signal	CH0OMODE	:std_logic_vector(1 downto 0);
signal	CH1OMODE	:std_logic_vector(1 downto 0);
signal	CH2OMODE	:std_logic_vector(1 downto 0);
signal	CH3OMODE	:std_logic_vector(1 downto 0);

signal	CHMASK		:std_logic_vector(3 downto 0);
signal	SREQ		:std_logic_vector(3 downto 0);

signal	CHPRD		:std_logic_vector(3 downto 0);
signal	CHPWR		:std_logic_vector(3 downto 0);
signal	CHPDOE		:std_logic_vector(3 downto 0);
signal	CH0PODAT	:std_logic_vector(7 downto 0);
signal	CH1PODAT	:std_logic_vector(7 downto 0);
signal	CH2PODAT	:std_logic_vector(7 downto 0);
signal	CH3PODAT	:std_logic_vector(7 downto 0);

signal	CHMEMRD		:std_logic_vector(3 downto 0);
signal	CHMEMWR		:std_logic_vector(3 downto 0);
signal	CHIORD		:std_logic_vector(3 downto 0);
signal	CHIOWR		:std_logic_vector(3 downto 0);

signal	CH0DADDR	:std_logic_vector(15 downto 0);
signal	CH1DADDR	:std_logic_vector(15 downto 0);
signal	CH2DADDR	:std_logic_vector(15 downto 0);
signal	CH3DADDR	:std_logic_vector(15 downto 0);

signal	CHDAOE		:std_logic_vector(3 downto 0);
signal	CHBUSREQ	:std_logic_vector(3 downto 0);
signal	CHBUSACK	:std_logic_vector(3 downto 0);

signal	STCLR		:std_logic;

component DMA1ch
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
end component;

begin
	
	-- Standard 8237 clear-byte-pointer register (PC-98 port 19h).
	-- EMM386 uses this instead of disabling the global controller.
	BYTE_CLEAR<='1' when PCS='1' and PWR='1' and PADDR="1100" else '0';

	DRQX<=DREQ when DRQlog='0' else not DREQ;
	DRQV<=DRQX or SREQ;
	
	DMA0	:DMA1ch port map(
		PADDR	=>PADDR(0),
		PRD		=>CHPRD(0),
		PWR		=>CHPWR(0),
		PRDATA	=>CH0PODAT,
		PWDATA	=>PWDATA,
		PDOE	=>CHPDOE(0),
		
		CONTEN	=>not CONTEN and not BYTE_CLEAR,
		CHEN	=>not CHMASK(0),
		DIRMODE	=>CH0TMODE,
		AUTOINI	=>CHAUTOINI(0),
		DEC_INCn=>CHADEC_INCn(0),
		OPMODE	=>CH0OMODE,
		
		DREQ	=>DRQV(0),
		BUSREQ	=>CHBUSREQ(0),
		BUSACK	=>CHBUSACK(0),
		DACK	=>DACKV(0),
		DADDR	=>CH0DADDR,
		DAOE	=>CHDAOE(0),
		MEMRD	=>CHMEMRD(0),
		MEMWR	=>CHMEMWR(0),
		IORD	=>CHIORD(0),
		IOWR	=>CHIOWR(0),
		IOWAIT	=>IOWAIT,
		IOACK	=>IOACK,
		MEMACK	=>MEMACK,
		TC		=>TCb(0),
		ACARRY	=>ACARRY(0),
		
		clk		=>clk,
		rstn	=>rstn
	);

	DMA1	:DMA1ch port map(
		PADDR	=>PADDR(0),
		PRD		=>CHPRD(1),
		PWR		=>CHPWR(1),
		PRDATA	=>CH1PODAT,
		PWDATA	=>PWDATA,
		PDOE	=>CHPDOE(1),
		
		CONTEN	=>not CONTEN and not BYTE_CLEAR,
		CHEN	=>not CHMASK(1),
		DIRMODE	=>CH1TMODE,
		AUTOINI	=>CHAUTOINI(1),
		DEC_INCn=>CHADEC_INCn(1),
		OPMODE	=>CH1OMODE,
		
		DREQ	=>DRQV(1),
		BUSREQ	=>CHBUSREQ(1),
		BUSACK	=>CHBUSACK(1),
		DACK	=>DACKV(1),
		DADDR	=>CH1DADDR,
		DAOE	=>CHDAOE(1),
		MEMRD	=>CHMEMRD(1),
		MEMWR	=>CHMEMWR(1),
		IORD	=>CHIORD(1),
		IOWR	=>CHIOWR(1),
		IOWAIT	=>IOWAIT,
		IOACK	=>IOACK,
		MEMACK	=>MEMACK,
		TC		=>TCb(1),
		ACARRY	=>ACARRY(1),
		
		clk		=>clk,
		rstn	=>rstn
	);

	DMA2	:DMA1ch port map(
		PADDR	=>PADDR(0),
		PRD		=>CHPRD(2),
		PWR		=>CHPWR(2),
		PRDATA	=>CH2PODAT,
		PWDATA	=>PWDATA,
		PDOE	=>CHPDOE(2),
		
		CONTEN	=>not CONTEN and not BYTE_CLEAR,
		CHEN	=>not CHMASK(2),
		DIRMODE	=>CH2TMODE,
		AUTOINI	=>CHAUTOINI(2),
		DEC_INCn=>CHADEC_INCn(2),
		OPMODE	=>CH2OMODE,
		
		DREQ	=>DRQV(2),
		BUSREQ	=>CHBUSREQ(2),
		BUSACK	=>CHBUSACK(2),
		DACK	=>DACKV(2),
		DADDR	=>CH2DADDR,
		DAOE	=>CHDAOE(2),
		MEMRD	=>CHMEMRD(2),
		MEMWR	=>CHMEMWR(2),
		IORD	=>CHIORD(2),
		IOWR	=>CHIOWR(2),
		IOWAIT	=>IOWAIT,
		IOACK	=>IOACK,
		MEMACK	=>MEMACK,
		TC		=>TCb(2),
		ACARRY	=>ACARRY(2),
		
		clk		=>clk,
		rstn	=>rstn
	);

	DMA3	:DMA1ch port map(
		PADDR	=>PADDR(0),
		PRD		=>CHPRD(3),
		PWR		=>CHPWR(3),
		PRDATA	=>CH3PODAT,
		PWDATA	=>PWDATA,
		PDOE	=>CHPDOE(3),
		
		CONTEN	=>not CONTEN and not BYTE_CLEAR,
		CHEN	=>not CHMASK(3),
		DIRMODE	=>CH3TMODE,
		AUTOINI	=>CHAUTOINI(3),
		DEC_INCn=>CHADEC_INCn(3),
		OPMODE	=>CH3OMODE,
		
		DREQ	=>DRQV(3),
		BUSREQ	=>CHBUSREQ(3),
		BUSACK	=>CHBUSACK(3),
		DACK	=>DACKV(3),
		DADDR	=>CH3DADDR,
		DAOE	=>CHDAOE(3),
		MEMRD	=>CHMEMRD(3),
		MEMWR	=>CHMEMWR(3),
		IORD	=>CHIORD(3),
		IOWR	=>CHIOWR(3),
		IOWAIT	=>IOWAIT,
		IOACK	=>IOACK,
		MEMACK	=>MEMACK,
		TC		=>TCb(3),
		ACARRY	=>ACARRY(3),
		
		clk		=>clk,
		rstn	=>rstn
	);
	
	Tc<=TCb;
	DACK<=DACKV when DACKlog='1' else not DACKV;
	
	CHPRD<=	"0000" when PCS='0' or PRD='0' else
			"0001" when PADDR(3 downto 1)="000" else
			"0010" when PADDR(3 downto 1)="001" else
			"0100" when PADDR(3 downto 1)="010" else
			"1000" when PADDR(3 downto 1)="011" else
			"0000";
	
	CHPWR<=	"0000" when PCS='0' or PWR='0' else
			"0001" when PADDR(3 downto 1)="000" else
			"0010" when PADDR(3 downto 1)="001" else
			"0100" when PADDR(3 downto 1)="010" else
			"1000" when PADDR(3 downto 1)="011" else
			"0000";
	
	PRDATA<=CH0PODAT when CHPDOE(0)='1' else
			CH1PODAT when CHPDOE(1)='1' else
			CH2PODAT when CHPDOE(2)='1' else
			CH3PODAT when CHPDOE(3)='1' else
			DRQV & TClat when PADDR="1000" else
			(others=>'0');
	PDOE<=	'1' when PCS='1' and PRD='1' else '0';

	process(clk,rstn)
	variable STREAD,lSTREAD	:std_logic;
	begin
		if(rstn='0')then
			STREAD:='0';
			lSTREAD:='0';
			STCLR<='0';
		elsif(clk' event and clk='1')then
			STCLR<='0';
			if(PCS='1' and PRD='1' and PADDR="0000")then
				STREAD:='1';
			else
				STREAD:='0';
			end if;
			if(lSTREAD='1' and STREAD='0')then
				STCLR<='1';
			end if;
			lSTREAD:=STREAD;
		end if;
	end process;
	
	process(clk,rstn)begin
		if(rstn='0')then
			TClat<=(others=>'0');
		elsif(clk' event and clk='1')then
			for i in 0 to 3 loop
				if(TCb(i)='1')then
					TClat(i)<='1';
				elsif(CHPWR(i)='1')then
					TClat(i)<='0';
				end if;
			end loop;
--			if(STCLR='1')then
--				TClat<=(others=>'0');
--			end if;
		end if;
	end process;
	
	process(clk,rstn)begin
		if(rstn='0')then
			INT<='0';
		elsif(clk' event and clk='1')then
			for i in 0 to 3 loop
				if(TCb(i)='1')then
					INT<='1';
				elsif(CHPWR(i)='1')then
					INT<='0';
				end if;
			end loop;
			if(STCLR='1')then
				INT<='0';
			end if;
		end if;
	end process;

	process(clk,rstn)begin
		if(rstn='0')then
			M2Men<='0';
			CH0AHOLD<='0';
			CONTEN<='0';
			COMPRESS<='0';
			ROTPRI<='0';
			WREXT<='0';
			DRQlog<='0';
			DACKlog<='0';
			CH0TMODE<=(others=>'0');
			CH1TMODE<=(others=>'0');
			CH2TMODE<=(others=>'0');
			CH3TMODE<=(others=>'0');
			CHAUTOINI<=(others=>'0');
			CH0OMODE<=(others=>'0');
			CH1OMODE<=(others=>'0');
			CH2OMODE<=(others=>'0');
			CH3OMODE<=(others=>'0');
			CHMASK<=(others=>'0');
			SREQ<=(others=>'0');
		elsif(clk' event and clk='1')then
			if(PCS='1' and PWR='1')then
				case PADDR is
				when "1000" =>
					M2Men<=PWDATA(0);
					CH0AHOLD<=PWDATA(1);
					CONTEN<=PWDATA(2);
					COMPRESS<=PWDATA(3);
					ROTPRI<=PWDATA(4);
					DRQlog<=PWDATA(5);
					DACKlog<=PWDATA(6);
				when "1001" =>
					case PWDATA(1 downto 0) is
					when "00" =>
						SREQ(0)<=PWDATA(2);
					when "01" =>
						SREQ(1)<=PWDATA(2);
					when "10" =>
						SREQ(2)<=PWDATA(2);
					when "11" =>
						SREQ(3)<=PWDATA(2);
					when others =>
					end case;
				when "1010" =>
					case PWDATA(1 downto 0) is
					when "00" =>
						CHMASK(0)<=PWDATA(2);
					when "01" =>
						CHMASK(1)<=PWDATA(2);
					when "10" =>
						CHMASK(2)<=PWDATA(2);
					when "11" =>
						CHMASK(3)<=PWDATA(2);
					when others =>
					end case;
				when "1011" =>
					case PWDATA(1 downto 0) is
					when "00" =>
						CH0TMODE<=PWDATA(3 downto 2);
						CHAUTOINI(0)<=PWDATA(4);
						CHADEC_INCn(0)<=PWDATA(5);
						CH0OMODE<=PWDATA(7 downto 6);
					when "01" =>
						CH1TMODE<=PWDATA(3 downto 2);
						CHAUTOINI(1)<=PWDATA(4);
						CHADEC_INCn(1)<=PWDATA(5);
						CH1OMODE<=PWDATA(7 downto 6);
					when "10" =>
						CH2TMODE<=PWDATA(3 downto 2);
						CHAUTOINI(2)<=PWDATA(4);
						CHADEC_INCn(2)<=PWDATA(5);
						CH2OMODE<=PWDATA(7 downto 6);
					when "11" =>
						CH3TMODE<=PWDATA(3 downto 2);
						CHAUTOINI(3)<=PWDATA(4);
						CHADEC_INCn(3)<=PWDATA(5);
						CH3OMODE<=PWDATA(7 downto 6);
					when others =>
					end case;
				when "1110" =>
					CHMASK<=(others=>'0');
				when "1111" =>
					CHMASK<=PWDATA(3 downto 0);
				when others =>
				end case;
			end if;
		end if;
	end process;
	
	process(clk,rstn)
	variable chsel	:integer range 0 to 4;
	variable chnum	:integer range 0 to 3;
	begin
		if(rstn='0')then
			CURPRI<=0;
			ACTCH<=4;
		elsif(clk' event and clk='1')then
			if(ACTCH=4)then
				chsel:=4;
				for i in 3 downto 0 loop
					chnum:=CURPRI+i;
					if(chnum>3)then
						chnum:=chnum-4;
					end if;
					if(CHBUSREQ(chnum)='1')then
						chsel:=chnum;
					end if;
				end loop;
				ACTCH<=chsel;
			else
				if(CHBUSREQ(ACTCH)='0')then
					ACTCH<=4;
					if(ROTPRI='1')then
						if(ACTCH=3)then
							CURPRI<=0;
						else
							CURPRI<=ACTCH+1;
						end if;
					else
						CURPRI<=0;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	BUSREQ<=CHBUSREQ(3) or CHBUSREQ(2) or CHBUSREQ(1) or CHBUSREQ(0);
	
	process(BUSACK,ACTCH)begin
		for i in 0 to 3 loop
			if(i=ACTCH)then
				CHBUSACK(i)<=BUSACK;
			else
				CHBUSACK(i)<='0';
			end if;
		end loop;
	end process;
	
	DADDR<=	CH0DADDR	when ACTCH=0 else
			CH1DADDR	when ACTCH=1 else
			CH2DADDR	when ACTCH=2 else
			CH3DADDR	when ACTCH=3 else
			(others=>'0');

	process(ACTCH,CHMEMRD,CHMEMWR,CHIORD,CHIOWR,CHDAOE)begin
		if(ACTCH<4)then
			MEMRD<=CHMEMRD(ACTCH);
			MEMWR<=CHMEMWR(ACTCH);
			IORD<=CHIORD(ACTCH);
			IOWR<=CHIOWR(ACTCH);
			DAOE<=CHDAOE(ACTCH);
		else
			MEMRD<='0';
			MEMWR<='0';
			IORD<='0';
			IOWR<='0';
			DAOE<='0';
		end if;
	end process;
	
	CURCH<=ACTCH;

end rtl;

			