LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity KBCONV is
generic(
	CLKCYC	:integer	:=20000;
	SFTCYC	:integer	:=400;
	RPSET		:integer	:=1
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
end KBCONV;

architecture MAIN of KBCONV is

component KBIF
generic(
	SFTCYC	:integer	:=400;		--kHz
	STCLK	:integer	:=150;		--usec
	TOUT	:integer	:=150		--usec
);
port(
	DATIN	:in std_logic_vector(7 downto 0);
	DATOUT	:out std_logic_vector(7 downto 0);
	WRn		:in std_logic;
	BUSY	:out std_logic;
	RXED	:out std_logic;
	RESET	:in std_logic;
	COL		:out std_logic;
	PERR	:out std_logic;
	
	KBCLKIN	:in	std_logic;
	KBCLKOUT :out std_logic;
	KBDATIN	:in std_logic;
	KBDATOUT :out std_logic;
	
	SFT		:in std_logic;
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

component  ktbln
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		q			: OUT STD_LOGIC_VECTOR (6 DOWNTO 0)
	);
END component;

component  ktble0
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		q			: OUT STD_LOGIC_VECTOR (6 DOWNTO 0)
	);
END component;

--component  keypress
--	PORT
--	(
--		address		: IN STD_LOGIC_VECTOR (6 DOWNTO 0);
--		clock		: IN STD_LOGIC  := '1';
--		data		: IN STD_LOGIC;
--		wren		: IN STD_LOGIC ;
--		q		: OUT STD_LOGIC
--	);
--END component;

signal	E0en	:std_logic;
signal	F0en	:std_logic;
signal	SFT		:std_logic;
signal	TBLADR	:std_logic_vector(7 downto 0);
signal	TBLDAT	:std_logic_vector(6 downto 0);
signal	NTBLDAT	:std_logic_vector(6 downto 0);
signal	E0TBLDAT:std_logic_vector(6 downto 0);
signal	semuen	:std_logic;
signal	keypress	:std_logic_vector(127 downto 0);

type KBSTATE_T is (
	KS_IDLE,
	KS_RESET,
	KS_RESET_BAT,
	KS_IDRD,
	KS_IDRD_ACK,
	KS_IDRD_LB,
	KS_IDRD_HB,
	KS_LEDS,
	KS_LEDW,
	KS_LEDB,
	KS_LEDS_ACK,
	KS_SETREPS,
	KS_SETREPW,
	KS_SETREPB,
	KS_SETREP_ACK,
	KS_RDTBL,
	KS_REP,
	KS_WINT
);

signal	KBSTATE	:KBSTATE_T;
signal	KB_TXDAT	:std_logic_vector(7 downto 0);
signal	KB_RXDAT	:std_logic_vector(7 downto 0);
signal	KB_WRn		:std_logic;
signal	KB_BUSY		:std_logic;
signal	KB_RXED		:std_logic;
signal	KB_RESET	:std_logic;
signal	KB_COL		:std_logic;
signal	KB_PERR		:std_logic;
signal	WAITCNT		:integer range 0 to 5;
constant waitcont	:integer	:=1;
constant waitsep	:integer	:=20;
constant waitccount	:integer	:=waitcont*SFTCYC;
constant waitscount	:integer	:=waitsep*SFTCYC;
signal	WAITSFT		:integer range 0 to waitscount;
signal	CAPSen		:std_logic;
signal	KANAen		:std_logic;
signal	nCAPS0		:std_logic;
signal	nKANA0		:std_logic;
signal	lCAPSf0		:std_logic;
signal	lKANAf0		:std_logic;
signal	pressed		:std_logic;
signal	presswd		:std_logic;
signal	presswr		:std_logic;

signal	KBDAT		:std_logic_vector(7 downto 0);
signal	STATUS		:std_logic_vector(7 downto 0);
signal	KBRST		:std_logic;
signal	KBRET		:std_logic;
signal	KBRDY		:std_logic;
signal	KBDOWNEN	:std_logic;
signal	DSR			:std_logic;
signal	BRK			:std_logic;
signal	dFE			:std_logic;
signal	dOE			:std_logic;
signal	dPE			:std_logic;
signal	TXEMP		:std_logic;
signal	RXRDY		:std_logic;
signal	TXRDY		:std_logic;
signal	RXED		:std_logic;
signal	cmdnum		:integer range 0 to 3;

-- Keep complete PS/2 bytes while the guest still owns the previous 8251 byte.
-- Prefixes and releases must not be discarded in KS_WINT/KS_REP. This queue
-- stays in clk; the existing pin synchronizers/KBIF remain the CDC boundary.
type KB_BYTE_QUEUE_T is array (0 to 15) of std_logic_vector(7 downto 0);
signal kb_queue : KB_BYTE_QUEUE_T;
signal kb_qread, kb_qwrite : integer range 0 to 15;
signal kb_qcount : integer range 0 to 16;
signal kb_qpop, kb_qactive, kb_qoverflow : std_logic;
signal kb_qdata : std_logic_vector(7 downto 0);
signal kb_clock_release : std_logic;
	
begin
--	MONOUT<="00000000" when KBSTATE=KS_IDLE else
--			"00000001" when KBSTATE=KS_CLRRAM or KBSTATE=KS_CLRRAM1 else
--			"00000010" when KBSTATE=KS_RESET or KBSTATE=KS_RESET_BAT else
--			"00000100" when KBSTATE=KS_IDRD or KBSTATE=KS_IDRD_ACK else
--			"00001000" when KBSTATE=KS_IDRD_LB or KBSTATE=KS_IDRD_HB else
--			"00010000" when KBSTATE=KS_LEDS or KBSTATE=KS_LEDB else
--			"00100000" when KBSTATE=KS_LEDS_ACK else
--			"01000000" when KBSTATE=KS_RDTBL or KBSTATE=KS_RDE0TBL else
--			"10000000" when KBSTATE=KS_RDRAM or KBSTATE=KS_WRRAM else
--			"00000000";
--	monout<= KB_RXDAT;
--	monout<=TBLADR;
	monout<='0' & TBLDAT;
--	monout<=WRDAT;
	
	process(clk)begin
		if(clk' event and clk='1')then
			semuen<=emuen;
		end if;
	end process;
	
	DSR<='0';
	BRK<='0';
	dFE<='0';
	dOE<=kb_qoverflow;
	dPE<='0';
	TXEMP<='1';
	TXRDY<='1';
	
	STATUS<=DSR & BRK & dFE & dOE & dPE & TXEMP & RXRDY & TXRDY;
	RDAT<=	KBDAT when ADDR='0' else STATUS;
	OE<=	'1' when CS='1' and RD='1' else '0';
	
	KBSFT	:sftclk generic map(CLKCYC,SFTCYC,1) port map("1",SFT,clk,rstn);
	
	KB	:KBIF port map(
	DATIN	=>KB_TXDAT,
	DATOUT	=>KB_RXDAT,
	WRn		=>KB_WRn,
	BUSY	=>KB_BUSY,
	RXED	=>KB_RXED,
	RESET	=>KB_RESET,
	COL		=>KB_COL,
	PERR	=>KB_PERR,
	
	KBCLKIN	=>KBCLKIN,
	KBCLKOUT=>kb_clock_release,
	KBDATIN	=>KBDATIN,
	KBDATOUT=>KBDATOUT,
	
	SFT		=>SFT,
	clk		=>clk,
	rstn	=>rstn
	);

-- Stop the keyboard before the queue fills. Two slots remain for a byte
-- already in flight and pin/receiver latency. Low means clock inhibit.
	KBCLKOUT<=kb_clock_release when kb_qcount<14 else '0';
	kb_qactive<='1' when KBSTATE=KS_IDLE or KBSTATE=KS_RDTBL or
		KBSTATE=KS_REP or KBSTATE=KS_WINT else '0';
	kb_qpop<='1' when KBSTATE=KS_IDLE and WAITCNT=0 and WAITSFT=0 and
		semuen='0' and kb_qcount>0 else '0';
	kb_qdata<=kb_queue(kb_qread);
	process(clk,rstn)
	variable push, pop : boolean;
	begin
		if rstn='0' then
			kb_qread<=0;kb_qwrite<=0;kb_qcount<=0;kb_qoverflow<='0';
		elsif rising_edge(clk) then
			if semuen='1' then
				kb_qread<=0;kb_qwrite<=0;kb_qcount<=0;kb_qoverflow<='0';
			else
				pop:=kb_qpop='1';
				push:=KB_RXED='1' and kb_qactive='1';
				if push and kb_qcount=16 and not pop then
					-- Defensive status for a device that ignores clock inhibition.
					kb_qoverflow<='1';push:=false;
				end if;
				if push then
					kb_queue(kb_qwrite)<=KB_RXDAT;
					if kb_qwrite=15 then kb_qwrite<=0;else kb_qwrite<=kb_qwrite+1;end if;
				end if;
				if pop then
					if kb_qread=15 then kb_qread<=0;else kb_qread<=kb_qread+1;end if;
				end if;
				if push and not pop then kb_qcount<=kb_qcount+1;
				elsif pop and not push then kb_qcount<=kb_qcount-1;end if;
			end if;
		end if;
	end process;

	emurxdat<=KB_RXDAT;
	emurx<=	'0' when emuen='0' else 
			KB_RXED when KBSTATE=KS_IDLE else
			'0';
	
	process(clk,rstn)
	variable iBITSEL	:integer range 0 to 7;
	begin
		if(rstn='0')then
			KBSTATE<=KS_RESET;
			E0EN<='0';
			F0EN<='0';
			KB_WRn<='1';
			KB_RESET<='0';
			WAITCNT<=0;
			WAITSFT<=0;
			CAPSen<='0';
			KANAen<='0';
			lKANAf0<='1';
			lCAPSf0<='1';
			nKANA0<='0';
			nCAPS0<='0';
			KB_TXDAT<=(others=>'0');
			presswr<='0';
			presswd<='0';
			RXED<='0';
		elsif(clk' event and clk='1')then
			KB_WRn<='1';
			presswr<='0';
			RXED<='0';
			if(WAITCNT>0)then
				WAITCNT<=WAITCNT-1;
			elsif(WAITSFT>0)then
				if(SFT='1')then
					WAITSFT<=WAITSFT-1;
				end if;
			else
				case KBSTATE is
				when KS_RESET =>
					if(KB_BUSY='0')then
						KB_TXDAT<=x"ff";
						KB_WRn<='0';
						KBSTATE<=KS_RESET_BAT;
					end if;
				when KS_RESET_BAT =>
					if(KB_RXED='1' and KB_RXDAT=x"aa")then
						WAITSFT<=waitscount;
						KBSTATE<=KS_IDRD;
					end if;
				when KS_IDRD =>
					if(KB_BUSY='0')then
						KB_TXDAT<=x"f2";
						KB_WRn<='0';
						KBSTATE<=KS_IDRD_ACK;
					end if;
				when KS_IDRD_ACK =>
					if(KB_RXED='1' and KB_RXDAT=x"fa")then
						KBSTATE<=KS_IDRD_LB;
					end if;
				when KS_IDRD_LB =>
					if(KB_RXED='1')then
						KBSTATE<=KS_IDRD_HB;
					end if;
				when KS_IDRD_HB =>
					if(KB_RXED='1')then
						WAITSFT<=waitscount;
						KBSTATE<=KS_LEDS;
					end if;
				when KS_LEDS =>
					if(KB_BUSY='0')then
						KB_TXDAT<=x"ed";
						KB_WRn<='0';
						KBSTATE<=KS_LEDW;
						WAITSFT<=1;
					end if;
				when KS_LEDW =>
					if(KB_BUSY='0')then
						WAITSFT<=waitccount;
						KBSTATE<=KS_LEDB;
					end if;
				when KS_LEDB =>
					if(KB_BUSY='0')then
						KB_TXDAT<="00000" & CAPSen & '0' & KANAen;	--assign KANA to SCRlock
						KB_WRn<='0';
						KBSTATE<=KS_LEDS_ACK;
					end if;
				when KS_LEDS_ACK =>
					if(KB_RXED='1')then
--					monout<=KB_RXDAT;
						if(KB_RXDAT=x"fa")then
							WAITSFT<=waitscount;
							if(RPSET=0)then
								KBSTATE<=KS_IDLE;
							else
								KBSTATE<=KS_SETREPS;
							end if;
						elsif(KB_RXDAT=x"fe")then
							WAITSFT<=waitscount;
							KBSTATE<=KS_LEDS;
						end if;
					end if;
				when KS_SETREPS =>
					if(KB_BUSY='0')then
						KB_TXDAT<=x"f3";
						KB_WRn<='0';
						KBSTATE<=KS_SETREPW;
					end if;
				when KS_SETREPW =>
					if(KB_BUSY='0')then
						WAITSFT<=waitccount;
						KBSTATE<=KS_SETREPB;
					end if;
				when KS_SETREPB =>
					if(KB_BUSY='0')then
						KB_TXDAT<="00100111";
						KB_WRn<='0';
						KBSTATE<=KS_SETREP_ACK;
					end if;
				when KS_SETREP_ACK =>
					if(KB_RXED='1')then
						if(KB_RXDAT=x"fa")then
							WAITSFT<=waitscount;
							KBSTATE<=KS_IDLE;
						else
							WAITSFT<=waitscount;
							KBSTATE<=KS_SETREPS;
						end if;
					end if;
				when KS_IDLE =>
					if(kb_qpop='1')then
						if(kb_qdata=x"e0")then
							E0en<='1';
						elsif(kb_qdata=x"f0")then
							F0en<='1';
						else
							KBSTATE<=KS_RDTBL;
							TBLADR<=kb_qdata;
							WAITCNT<=2;
						end if;
					end if;
				when KS_RDTBL =>
					if(TBLDAT="1111111")then
						E0en<='0';
						F0en<='0';
						KBSTATE<=KS_IDLE;
					else
						if(F0en='1')then
							if(TBLDAT="1110001" or TBLDAT="1110010")then
								E0en<='0';
								F0en<='0';
								KBSTATE<=KS_IDLE;
							else
								KBDAT<='1' & TBLDAT;
								RXED<='1';
								KBSTATE<=KS_WINT;
							end if;
							presswd<='0';
							presswr<='1';
						else
							if(pressed='1')then
								if(TBLDAT(6 downto 4)="111")then
									E0en<='0';
									F0en<='0';
									KBSTATE<=KS_IDLE;
								else
									KBDAT<='1' & TBLDAT;	--break
									RXED<='1';
									KBSTATE<=KS_REP;
									WAITCNT<=5;
								end if;
							else
								case TBLDAT is
								when "1110001" =>	--CAPS
									KBDAT<=CAPSen & TBLDAT;
									CAPSen<=not CAPSen;
								when "1110010" =>	--KANA
									KBDAT<=KANAen & TBLDAT;
									KANAen<=not KANAen;
								when others =>
									KBDAT<='0' & TBLDAT;
								end case;
								presswd<='1';
								presswr<='1';
								RXED<='1';
								KBSTATE<=KS_WINT;
							end if;
						end if;
						WAITCNT<=1;
					end if;
				when KS_REP =>
					if(RXRDY='0')then
						KBDAT<='0' & TBLDAT;	--mark
						RXED<='1';
						KBSTATE<=KS_WINT;
						-- RXRDY is registered from RXED on the following edge.
						-- Do not mistake that publication cycle for a guest read.
						WAITCNT<=1;
					end if;
				when KS_WINT =>
					if(RXRDY='0')then
						E0en<='0';
						F0en<='0';
						if(TBLDAT="1110001" or TBLDAT="1110010")then
							KBSTATE<=KS_LEDS;
						else
							KBSTATE<=KS_IDLE;
						end if;
					end if;
				when others =>
					KBSTATE<=KS_IDLE;
				end case;
			end if;
		end if;
	end process;
	
	NTBL	:ktbln port map(TBLADR,clk,NTBLDAT);
	E0TBL	:ktble0 port map(TBLADR,clk,E0TBLDAT);
	TBLDAT<=E0TBLDAT when E0en='1' else NTBLDAT;
--	KP		:keypress port map(TBLDAT,clk,presswd,presswr,pressed);
	
	process(clk,rstn)
	variable ikey	:integer range 0 to 127;
	begin
		if(rstn='0')then
			keypress<=(others=>'0');
		elsif(clk' event and clk='1')then
			ikey:=conv_integer(TBLDAT);
			if(presswr='1')then
				keypress(ikey)<=presswd;
			end if;
			pressed<=keypress(ikey);
		end if;
	end process;
	
	process(clk,rstn)begin
		if(rstn='0')then
			KBRST<='0';
			KBRET<='0';
			KBRDY<='1';
			KBDOWNEN<='0';
			cmdnum<=0;
		elsif(clk' event and clk='1')then
			if(WR='1')then
				case ADDR is
				when '0' =>
				when '1' =>
					case cmdnum is
					when 0 =>
						if(WDAT(1 downto 0)="00")then
							cmdnum<=3;
						else
							cmdnum<=1;
						end if;
					when 1 =>
						cmdnum<=2;
					when 2 =>
						cmdnum<=3;
					when 3 =>
						if(WDAT(6)='1')then
							KBRST<='0';
							KBRET<='0';
							KBRDY<='1';
							KBDOWNEN<='0';
							cmdnum<=0;
						else
							KBRST<=WDAT(3);
							KBRET<=not WDAT(1);
							KBRDY<=not WDAT(5);
							KBDOWNEN<=WDAT(0);
						end if;
					when others =>
						cmdnum<=3;
					end case;
				when others =>
				end case;
			end if;
		end if;
	end process;
	
	process(clk,rstn)
	variable dRD,lRD	:std_logic;
	begin
		if(rstn='0')then
			RXRDY<='0';
		elsif(clk' event and clk='1')then
			if(CS='1' and ADDR='0' and RD='1')then
				dRD:='1';
			else
				dRD:='0';
			end if;
			if(RXED='1')then
				RXRDY<='1';
			elsif(dRD='0' and lRD='1')then
				RXRDY<='0';
			end if;
			lRD:=dRD;
		end if;
	end process;
	INT<=RXRDY;
	
end MAIN;
