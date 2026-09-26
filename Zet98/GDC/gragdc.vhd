LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;
	USE	IEEE.STD_LOGIC_ARITH.ALL;

entity GRAGDC is
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
	INTR	:out std_logic;
	
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
end GRAGDC;

architecture rtl of GRAGDC is

component gdcfifo
	PORT
	(
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (8 DOWNTO 0);
		rdaddress		: IN STD_LOGIC_VECTOR (3 DOWNTO 0);
		wraddress		: IN STD_LOGIC_VECTOR (3 DOWNTO 0);
		wren		: IN STD_LOGIC  := '0';
		q		: OUT STD_LOGIC_VECTOR (8 DOWNTO 0)
	);
END component;

signal	gdcreset	:std_logic;
signal	COMMAND		:std_logic_vector(7 downto 0);
signal	RFIFOADDR	:std_logic_vector(3 downto 0);
signal	WNFIFOADDR	:std_logic_vector(3 downto 0);
signal	WFIFOADDR	:std_logic_vector(3 downto 0);
signal	STATUS		:std_logic_vector(7 downto 0);
signal	RDATA		:std_logic_vector(7 downto 0);
signal	GDC_RDATx	:std_logic_vector(15 downto 0);
signal	GDC_WDATx	:std_logic_vector(15 downto 0);
signal	sDMAEXEC	:std_logic;
signal	sDRAWING	:std_logic;
signal	sFIFOE		:std_logic;
signal	sFIFOF		:std_logic;
signal	sDREADY		:std_logic;

signal	mWR,lWR			:std_logic;
signal	FIFOWDAT,FIFORDAT	:std_logic_vector(8 downto 0);
signal	FIFOWR		:std_logic;
signal	FIFORD		:std_logic;
signal	fifoexist	:std_logic;
signal	PARNUM		:integer range 0 to 15;
-- PRAM is one 16-byte space, not two independently wrapping 8-byte banks.
-- 16 is the exhausted state: excess bytes are ignored until a new command.
signal	PRAMADDR	:integer range 0 to 16;
signal	RDNUM		:integer range 0 to 15;
signal	RNUMCLR		:std_logic;
signal	DATRD		:std_logic;

signal	r_VRAMSEL	:std_logic;
signal	r_CRAMSEL	:std_logic;
signal	r_CZOOM		:std_logic_vector(3 downto 0);
signal	r_PITCH		:std_logic_vector(7 downto 0);

signal	D_MODE		:std_logic_vector(4 downto 0);
constant DM_DOT		:std_logic_vector(4 downto 0)	:="00000";
constant DM_LINE	:std_logic_vector(4 downto 0)	:="00001";
constant DM_CHAR	:std_logic_vector(4 downto 0)	:="00010";
constant DM_CIRCLE	:std_logic_vector(4 downto 0)	:="00100";
constant DM_RECT	:std_logic_vector(4 downto 0)	:="01000";
constant DM_CHARI	:std_logic_vector(4 downto 0)	:="10010";
type D_OP_T	is(
	DO_DRAW,
	DO_READ,
	DO_WRITE,
	DO_CHAR
);
signal	D_OP	:D_OP_T;
signal	D_DIR		:std_logic_vector(2 downto 0);
signal	D_DC		:std_logic_vector(13 downto 0);
signal	D_DGD		:std_logic;
signal	D_D			:std_logic_vector(13 downto 0);
signal	D_D2		:std_logic_vector(13 downto 0);
signal	D_D1		:std_logic_vector(13 downto 0);
signal	D_DM		:std_logic_vector(13 downto 0);
signal	D_PTN		:std_logic_vector(15 downto 0);
signal	D_TX0		:std_logic_vector(7 downto 0);
signal	D_TX1		:std_logic_vector(7 downto 0);
signal	D_TX2		:std_logic_vector(7 downto 0);
signal	D_TX3		:std_logic_vector(7 downto 0);
signal	D_TX4		:std_logic_vector(7 downto 0);
signal	D_TX5		:std_logic_vector(7 downto 0);
signal	D_TX6		:std_logic_vector(7 downto 0);
signal	D_TX7		:std_logic_vector(7 downto 0);
signal	D_BEGINA	:std_logic_vector(17 downto 0);
signal	D_BEGIND	:std_logic_vector(3 downto 0);
signal	D_WRMODE	:std_logic_vector(1 downto 0);
constant DW_SET		:std_logic_vector(1 downto 0)	:="00";
constant DW_XOR		:std_logic_vector(1 downto 0)	:="01";
constant DW_NAND	:std_logic_vector(1 downto 0)	:="10";
constant DW_OR		:std_logic_vector(1 downto 0)	:="11";
signal	DRAW_BEGIN	:std_logic;
signal	DRAW_BUSY	:std_logic;
signal	D_BEGINDi	:integer range 0 to 15;
signal	D_CURADDR	:std_logic_vector(17 downto 0);
signal	D_CURDOT	:integer range 0 to 15;
signal	D_NUM		:std_logic_vector(13 downto 0);
signal	D_NUM1		:std_logic_vector(13 downto 0);
signal	ADDRWR		:std_logic;
type D_STATE_T is(
	DS_IDLE,
	DS_READ,
	DS_READW,
	DS_WRITE,
	DS_WRITEW,
	DS_READ2,
	DS_READ2W,
	DS_WRITE2,
	DS_WRITE2W,
	DS_READ3,
	DS_READ3W,
	DS_WRITE3,
	DS_WRITE3W,
	DS_READ4,
	DS_READ4W,
	DS_WRITE4,
	DS_WRITE4W,
	DS_NEXT
);
signal	D_STATE	:D_STATE_T;
signal	divina	:std_logic_vector(30 downto 0);
signal	divinb	:std_logic_vector(30 downto 0);
signal	divq	:std_logic_vector(30 downto 0);
signal	divbgn	:std_logic;
signal	D_SUM	:std_logic_vector(17 downto 0);
signal	D_SUMCLR:std_logic;
signal	D_SUMADD:std_logic;
signal	D_SUMINC:std_logic;
signal	RDEXIST	:std_logic;
signal	NUMRDAT	:integer range 0 to 15;
signal	rdtmp	:std_logic_vector(7 downto 0);
signal	wrtmp	:std_logic_vector(7 downto 0);

signal	circlecalc	:std_logic;
signal	circlebusy	:std_logic;
signal	circleY	:std_logic_vector(13 downto 0);
signal	lastY	:std_logic_vector(13 downto 0);
signal	INTER	:std_logic;

subtype RDDAT_LAT_TYPE is std_logic_vector(7 downto 0); 
type RDDAT_LAT_ARRAY is array (natural range <>) of RDDAT_LAT_TYPE; 
signal	RDDAT	:RDDAT_LAT_ARRAY(0 to 15);
signal	D_RDDONE	:std_logic;
signal	RDED		:std_logic;
signal	D_WRDAT		:std_logic_vector(7 downto 0);


component div
generic(
	bitwidth	:integer	:=16
);
port(
	A		:in std_logic_vector(bitwidth-1 downto 0);
	D		:in std_logic_vector(bitwidth-1 downto 0);
	
	Q		:out std_logic_vector(bitwidth-1 downto 0);
	R		:out std_logic_vector(bitwidth-1 downto 0);
	
	start	:in std_logic;
	busy	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component calccircle
generic(
	dwidth	:integer	:=8
);
port(
	r		:in std_logic_vector(dwidth-1 downto 0);
	x		:in std_logic_vector(dwidth-1 downto 0);
	calc	:in std_logic;
	
	y		:out std_logic_vector(dwidth-1 downto 0);
	busy	:out std_logic;
	done	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;
 
begin
	INTR<=INTER;
	STATUS<=LPEND & HRTC & VRTC & sDMAEXEC & sDRAWING & sFIFOE & sFIFOF & sDREADY;
	sDMAEXEC<='0';
	sDRAWING<=DRAW_BUSY;
	sFIFOE<=	'1' when RFIFOADDR=WNFIFOADDR else '0';
	sFIFOF<=	'1' when (WNFIFOADDR+"0001")=RFIFOADDR else '0';
	fifoexist<=	'0' when RFIFOADDR=WNFIFOADDR else '1';
	sDREADY<=RDEXIST;

	mWR<='1' when WR='1' and CS='1' and ADDR(1)='0' else '0';
	
	process(clk,rstn)begin
		if(rstn='0')then
			lWR<='0';
			WFIFOADDR<=(others=>'1');
			WNFIFOADDR<=(others=>'0');
			FIFOWR<='0';
			FIFOWDAT<=(others=>'0');
		elsif(clk' event and clk='1')then
			FIFOWR<='0';
			if(gdcreset='1')then
				lWR<='0';
				WFIFOADDR<=(others=>'1');
				WNFIFOADDR<=(others=>'0');
				FIFOWR<='0';
				FIFOWDAT<=(others=>'0');
			elsif(mWR='1' and (WNFIFOADDR+x"1"/=RFIFOADDR))then
				WFIFOADDR<=WNFIFOADDR;
				FIFOWR<='1';
				FIFOWDAT<=ADDR(0) & DIN;
			elsif(lWR='1' and mWR='0' and (WFIFOADDR+"0001")/=RFIFOADDR)then
				WNFIFOADDR<=WNFIFOADDR+1;
			end if;
			lWR<=mWR;
		end if;
	end process;
	
	
	
	DOUT<=	STATUS 	when ADDR="00" else
			RDATA	when ADDR="01" else
			"0000000" & r_VRAMSEL when ADDR="10" else
			"0000000" & r_CRAMSEL when ADDR="11" else
			(others=>'0');
	
	DOE<=	'1' when CS='1' and RD='1' else
			'0';
		
	FIFO	:gdcfifo port map(clk,FIFOWDAT,RFIFOADDR,WFIFOADDR,FIFOWR,FIFORDAT);
	
	process(clk,rstn)
	variable nwait	:integer range 0 to 2;
	begin
		if(rstn='0')then
			RFIFOADDR<=(others=>'0');
			COMMAND<=x"ff";
			PARNUM<=0;
			PRAMADDR<=16;
			gdcreset<='0';
			RNUMCLR<='0';
			nwait:=0;
			GRAPHEN<='0';
			D_MODE<=(others=>'0');
			D_DIR<=(others=>'0');
			D_DC<=(others=>'0');
			D_DGD<='0';
			D_D<=(others=>'0');
			D_D2<=(others=>'0');
			D_D1<=(others=>'0');
			D_DM<=(others=>'0');
			D_PTN<=(others=>'0');
			D_TX0<=(others=>'0');
			D_TX1<=(others=>'0');
			D_TX2<=(others=>'0');
			D_TX3<=(others=>'0');
			D_TX4<=(others=>'0');
			D_TX5<=(others=>'0');
			D_TX6<=(others=>'0');
			D_TX7<=(others=>'0');
			D_BEGINA<=(others=>'0');
			D_BEGIND<=(others=>'0');
			D_WRMODE<=(others=>'0');
			VZOOM<=(others=>'0');
			BASEADDR0<=(others=>'0');
			BASEADDR1<=(others=>'0');
			SL0<=(others=>'0');
			SL1<=(others=>'0');
			IM<='0';
			r_PITCH<=(others=>'0');
			DOTPLINE<=(others=>'0');
			DRAW_BEGIN<='0';
			NUMRDAT<=0;
			wrtmp<=(others=>'0');
			rdtmp<=(others=>'0');
			divbgn<='0';
			INTER<='0';
			ADDRWR<='0';
			D_OP<=DO_DRAW;
			D_WRDAT<=(others=>'0');
		elsif(clk' event and clk='1')then
			gdcreset<='0';
			RNUMCLR<='0';
			DRAW_BEGIN<='0';
			divbgn<='0';
			ADDRWR<='0';
			if(nwait>0)then
				nwait:=nwait-1;
			elsif(gdcreset='1')then
				GRAPHEN<='0';
				D_MODE<=(others=>'0');
				D_DIR<=(others=>'0');
				D_DC<=(others=>'0');
				D_DGD<='0';
				D_D<=(others=>'0');
				D_D2<=(others=>'0');
				D_D1<=(others=>'0');
				D_DM<=(others=>'0');
				D_PTN<=(others=>'0');
				D_TX0<=(others=>'0');
				D_TX1<=(others=>'0');
				D_TX2<=(others=>'0');
				D_TX3<=(others=>'0');
				D_TX4<=(others=>'0');
				D_TX5<=(others=>'0');
				D_TX6<=(others=>'0');
				D_TX7<=(others=>'0');
				VZOOM<=(others=>'0');
				D_BEGINA<=(others=>'0');
				D_BEGIND<=(others=>'0');
				D_WRMODE<=(others=>'0');
				BASEADDR0<=(others=>'0');
				BASEADDR1<=(others=>'0');
				SL0<=(others=>'0');
				SL1<=(others=>'0');
				IM<='0';
				r_PITCH<=(others=>'0');
				DOTPLINE<=(others=>'0');
				DRAW_BEGIN<='0';
				NUMRDAT<=0;
				INTER<='0';
				RDDAT<=(others=>x"00");
				D_OP<=DO_DRAW;
				D_WRDAT<=(others=>'0');
			elsif(DRAW_BUSY='0' and fifoexist='1')then
				if(FIFORDAT(8)='1')then		--command
					NUMRDAT<=0;
					COMMAND<=FIFORDAT(7 downto 0);
					PARNUM<=0;
					RNUMCLR<='1';
					case FIFORDAT(7 downto 0) is
					when x"00" =>	--RESET1
						gdcreset<='1';
					when x"6b" | x"0d" =>
						GRAPHEN<='1';
					when x"0c" =>
						GRAPHEN<='0';
					when x"6c" =>
						D_OP<=DO_DRAW;
						DRAW_BEGIN<='1';
					when x"68" =>
						D_OP<=DO_READ;
						DRAW_BEGIN<='1';
					when x"70" | x"71" | x"72" | x"73" |
						 x"74" | x"75" | x"76" | x"77" =>
						PRAMADDR<=conv_integer(FIFORDAT(3 downto 0));
					when x"20" | x"21" | x"22" | x"23" |
						x"30" | x"31" | x"32" | x"33" |
						x"38" | x"39" | x"3a" | x"3b" =>
						D_WRMODE<=FIFORDAT(1 downto 0);
						D_OP<=DO_WRITE;
						DRAW_BEGIN<='1';
					when x"a0" | x"a1" | x"a2" | x"a3" |
						x"b0" | x"b1" | x"b2" | x"b3" |
						x"b8" | x"b9" | x"ba" | x"bb" =>
						D_WRMODE<=FIFORDAT(1 downto 0);
						D_OP<=DO_READ;
						DRAW_BEGIN<='1';
					when x"78" | x"79" | x"7a" | x"7b" |
						 x"7c" | x"7d" | x"7e" | x"7f" =>
						PRAMADDR<=conv_integer(FIFORDAT(3 downto 0));
					when x"e0" =>
						RDDAT(0)<=D_CURADDR(7 downto 0);
						RDDAT(1)<=D_CURADDR(15 downto 8);
						RDDAT(2)<="000000" & D_CURADDR(17 downto 16);
						RDDAT(3)<=conv_std_logic_vector(D_CURDOT,8);
						RDDAT(4)<=x"00";
						NUMRDAT<=5;
					when others =>
					end case;
				else
					case COMMAND is
					when x"0e" | x"0f" =>
						case PARNUM is
						when 0 =>
							INTER<=FIFORDAT(3);
						when others =>
						end case;
					when x"20" | x"21" | x"22" | x"23" |
						x"30" | x"31" | x"32" | x"33" |
						x"38" | x"39" | x"3a" | x"3b" =>
						D_WRDAT<=FIFORDAT(7 downto 0);
						D_OP<=DO_WRITE;
						DRAW_BEGIN<='1';
					when x"70" | x"71" | x"72" | x"73" |
						 x"74" | x"75" | x"76" | x"77" |
						 x"78" | x"79" | x"7a" | x"7b" |
						 x"7c" | x"7d" | x"7e" | x"7f" =>
						case PRAMADDR is
						when 0 =>
							BASEADDR0(7 downto 0)<=FIFORDAT(7 downto 0);
						when 1 =>
							BASEADDR0(15 downto 8)<=FIFORDAT(7 downto 0);
						when 2 =>
							BASEADDR0(17 downto 16)<=FIFORDAT(1 downto 0);
							SL0(3 downto 0)<=FIFORDAT(7 downto 4);
						when 3 =>
							SL0(9 downto 4)<=FIFORDAT(5 downto 0);
							IM<=FIFORDAT(6);
						when 4 =>
							BASEADDR1(7 downto 0)<=FIFORDAT(7 downto 0);
						when 5 =>
							BASEADDR1(15 downto 8)<=FIFORDAT(7 downto 0);
						when 6 =>
							BASEADDR1(17 downto 16)<=FIFORDAT(1 downto 0);
							SL1(3 downto 0)<=FIFORDAT(7 downto 4);
						when 7 =>
							SL1(9 downto 4)<=FIFORDAT(5 downto 0);
							IM<=FIFORDAT(6);
						when 8 =>
							D_PTN(7 downto 0)<=FIFORDAT(7 downto 0);
							D_TX0<=FIFORDAT(7 downto 0);
						when 9 =>
							D_PTN(15 downto 8)<=FIFORDAT(7 downto 0);
							D_TX1<=FIFORDAT(7 downto 0);
						when 10 =>
							D_TX2<=FIFORDAT(7 downto 0);
						when 11 =>
							D_TX3<=FIFORDAT(7 downto 0);
						when 12 =>
							D_TX4<=FIFORDAT(7 downto 0);
						when 13 =>
							D_TX5<=FIFORDAT(7 downto 0);
						when 14 =>
							D_TX6<=FIFORDAT(7 downto 0);
						when 15 =>
							D_TX7<=FIFORDAT(7 downto 0);
						when others =>
						end case;
						if(PRAMADDR<16)then
							PRAMADDR<=PRAMADDR+1;
						end if;
					when x"4b" =>
						case PARNUM is
						when 0 =>
							DOTPLINE<=FIFORDAT(4 downto 0);
						when others =>
						end case;
					when x"46" =>
						VZOOM<=FIFORDAT(3 downto 0);
					when x"47" =>
						case PARNUM is
						when 0 =>
							r_PITCH<=FIFORDAT(7 downto 0);
						when others =>
						end case;
					when x"49" =>
						case PARNUM is
						when 0 =>
							D_BEGINA(7 downto 0)<=FIFORDAT(7 downto 0);
							ADDRWR<='1';
						when 1 =>
							D_BEGINA(15 downto 8)<=FIFORDAT(7 downto 0);
							ADDRWR<='1';
						when 2 =>
							D_BEGINA(17 downto 16)<=FIFORDAT(1 downto 0);
							D_BEGIND<=FIFORDAT(7 downto 4);
							ADDRWR<='1';
						when others =>
						end case;
					when x"4c" =>
						case PARNUM is
						when 0 =>
							D_DIR<=FIFORDAT(2 downto 0);
							D_MODE<=FIFORDAT(7 downto 3);
						when 1 =>
							D_DC(7 downto 0)<=FIFORDAT(7 downto 0);
						when 2 =>
							D_DC(13 downto 8)<=FIFORDAT(5 downto 0);
							D_DGD<=FIFORDAT(6);
						when 3 =>
							D_D(7 downto 0)<=FIFORDAT(7 downto 0);
						when 4 =>
							D_D(13 downto 8)<=FIFORDAT(5 downto 0);
						when 5 =>
							D_D2(7 downto 0)<=FIFORDAT(7 downto 0);
						when 6 =>
							D_D2(13 downto 8)<=FIFORDAT(5 downto 0);
						when 7 =>
							D_D1(7 downto 0)<=FIFORDAT(7 downto 0);
						when 8 =>
							D_D1(13 downto 8)<=FIFORDAT(5 downto 0);
							divbgn<='1';
						when 9 =>
							D_DM(7 downto 0)<=FIFORDAT(7 downto 0);
						when 10 =>
							D_DM(13 downto 8)<=FIFORDAT(5 downto 0);
						when others =>
						end case;
					when others =>
					end case;
					-- Preserve the four-bit counter used by streaming WDAT.
					PARNUM<=(PARNUM+1) mod 16;
				end if;
				RFIFOADDR<=RFIFOADDR+x"1";
				nwait:=1;
			elsif(RDED='1')then
				case COMMAND is
				when x"a0" | x"a1" | x"a2" | x"a3" =>
					if(RDNUM=1)then
						D_OP<=DO_READ;
						DRAW_BEGIN<='1';
					end if;
				when x"b0" | x"b1" | x"b2" | x"b3" |
					 x"b8" | x"b9" | x"ba" | x"bb" =>
					D_OP<=DO_READ;
					DRAW_BEGIN<='1';
				when others=>
				end case;
			end if;
			if(D_RDDONE='1')then
				case COMMAND is
				when x"a0" | x"a1" | x"a2" | x"a3" =>
					RDDAT(0)<=GDC_WDATx(7 downto 0);
					RDDAT(1)<=GDC_WDATx(15 downto 8);
				when x"b0" | x"b1" | x"b2" | x"b3" =>
					RDDAT(0)<=GDC_WDATx(7 downto 0);
				when x"b8" | x"b9" | x"ba" | x"bb" =>
					RDDAT(0)<=GDC_WDATx(15 downto 8);
				when others =>
				end case;
			end if;
		end if;
	end process;
	
	PITCH<=r_PITCH;
	
	process(clk,rstn)begin
		if(rstn='0')then
			r_VRAMSEL	<='0';
			r_CRAMSEL	<='0';
		elsif(clk' event and clk='1')then
			if(CS='1' and WR='1')then
				case ADDR is
				when "10" =>
					r_VRAMSEL<=DIN(0);
				when "11" =>
					r_CRAMSEL<=DIN(0);
				when others =>
				end case;
			end if;
		end if;
	end process;

	VRAMSEL<=r_VRAMSEL;
	CRAMSEL<=r_CRAMSEL;
	
	DATRD<='1' when CS='1' and ADDR="01" and RD='1' else '0';

	process(clk,rstn)
	variable lRD	:std_logic;
	begin
		if(rstn='0')then
			RDNUM<=0;
			lRD:='0';
			RDED<='0';
		elsif(clk' event and clk='1')then
			RDED<='0';
			if(RNUMCLR='1')then
				RDNUM<=0;
			elsif(lRD='1' and DATRD='0')then
				RDNUM<=RDNUM+1;
				RDED<='1';
			end if;
			lRD:=DATRD;
		end if;
	end process;

	RDATA<=RDDAT(RDNUM);
	
	RDEXIST<='1' when NUMRDAT>RDNUM else '0';
	DRAW_BUSY<=	'1' when DRAW_BEGIN='1' else
				'0' when D_STATE=DS_IDLE else
				'1';
	
	D_BEGINDi<=conv_integer(D_BEGIND);
	
	D_NUM1(13 downto 1)<=(others=>'0');
	D_NUM1(0)<='1';
	
	divina(30 downto 17)<=D_D1;
	divina(16 downto 0)<=(others=>'0');
	divinb(30 downto 15)<=(others=>'0');
	divinb(14 downto 0)<=D_DC & '0';
	
	divs	:div generic map(31)port map(
		A		=>divina,
		D		=>divinb,
		
		Q		=>divq,
		R		=>open,
		
		start	=>divbgn,
		busy	=>open,
		
		clk	=>clk,
		rstn	=>rstn
	);

	process(clk,rstn)begin
		if(rstn='0')then
			D_SUM<=(others=>'0');
		elsif(clk' event and clk='1')then
			if(D_SUMCLR='1')then
				D_SUM<=(others=>'0');
			elsif(D_SUMADD='1')then
				D_SUM<=('0' & D_SUM(16 downto 0))+divq(17 downto 0);
			end if;
		end if;
	end process;
	
	D_SUMINC<=D_SUM(17);
	
	GDC_RDATx<=GDC_RDAT(8) & GDC_RDAT(9) & GDC_RDAT(10) & GDC_RDAT(11) & GDC_RDAT(12) & GDC_RDAT(13) & GDC_RDAT(14) & GDC_RDAT(15) & GDC_RDAT(0) & GDC_RDAT(1) & GDC_RDAT(2) & GDC_RDAT(3) & GDC_RDAT(4) & GDC_RDAT(5) & GDC_RDAT(6) & GDC_RDAT(7);
	
	process(clk,rstn)
	variable mwait	:integer range 0 to 3;
	variable vaddr	:std_logic_vector(17 downto 0);
	begin
		if(rstn='0')then
			D_STATE<=DS_IDLE;
			GDC_ADDR<=(others=>'0');
			GDC_RD<='0';
			GDC_WR<='0';
			D_NUM<=(others=>'0');
			D_SUMCLR<='0';
			D_SUMADD<='0';
			circlecalc<='0';
			D_RDDONE<='0';
		elsif(clk' event and clk='1')then
			D_SUMCLR<='0';
			D_SUMADD<='0';
			circlecalc<='0';
			D_RDDONE<='0';
			if(ADDRWR='1')then
				D_CURADDR<=D_BEGINA;
				D_CURDOT<=D_BEGINDi;
			end if;
			if(mwait/=0)then
				mwait:=mwait-1;
			else
				case D_OP is
				when DO_DRAW =>
					case D_MODE is
					when DM_DOT =>
						case D_STATE is
						when DS_IDLE =>
							if(DRAW_BEGIN='1')then
								GDC_ADDR<=D_CURADDR;
								GDC_RD<='1';
								mwait:=1;
								D_STATE<=DS_READ;
							end if;
						when DS_READ =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<='1';
										when DW_XOR =>
											GDC_WDATx(i)<=not GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<='0';
										when DW_OR =>
											GDC_WDATx(i)<='1';
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								mwait:=1;
								D_STATE<=DS_READW;
							end if;
						when DS_READW =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								D_STATE<=DS_WRITE;
							end if;
						when DS_WRITE =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								D_STATE<=DS_WRITEW;
							end if;
						when DS_WRITEW =>
							if(GDC_MACK='0')then
								D_STATE<=DS_IDLE;
							end if;
						when others =>
							D_STATE<=DS_IDLE;
						end case;
					when DM_LINE =>
						case D_STATE is
						when DS_IDLE =>
							if(DRAW_BEGIN='1')then
								GDC_ADDR<=D_CURADDR;
								GDC_RD<='1';
								D_NUM<=D_DC;
								D_SUMCLR<='1';
								mwait:=1;
								D_STATE<=DS_READ;
							end if;
						when DS_READ =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								D_SUMADD<='1';
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<=D_PTN(i);
										when DW_XOR =>
											GDC_WDATx(i)<=D_PTN(i) xor GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<=GDC_RDATx(i) and (not D_PTN(i));
										when DW_OR =>
											GDC_WDATx(i)<=GDC_RDATx(i) or D_PTN(i);
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								mwait:=1;
								D_STATE<=DS_READW;
							end if;
						when DS_READW =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								D_STATE<=DS_WRITE;
							end if;
						when DS_WRITE =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								if(D_NUM=D_NUM1)then
									D_STATE<=DS_IDLE;
								else
									D_NUM<=D_NUM-1;
									vaddr:=D_CURADDR;
									case D_DIR is
									when "000" | "111" =>
										vaddr:=vaddr+r_PITCH(6 downto 0);
									when "001" | "010" =>
										if(D_CURDOT=15)then
											vaddr:=vaddr+1;
											D_CURDOT<=0;
										else
											D_CURDOT<=D_CURDOT+1;
										end if;
									when "011" | "100" =>
										vaddr:=vaddr-r_PITCH(6 downto 0);
									when "101" | "110" =>
										if(D_CURDOT=0)then
											vaddr:=vaddr-1;
											D_CURDOT<=15;
										else
											D_CURDOT<=D_CURDOT-1;
										end if;
									when others =>
									end case;
									
									if(D_SUMINC='1')then
										case D_DIR is
										when "000" | "011" =>
											if(D_CURDOT=15)then
												vaddr:=vaddr+1;
												D_CURDOT<=0;
											else
												D_CURDOT<=D_CURDOT+1;
											end if;
										when "001" | "110" =>
											vaddr:=vaddr+r_PITCH(6 downto 0);
										when "010" | "101" =>
											vaddr:=vaddr-r_PITCH(6 downto 0);
										when "100" | "111" =>
											if(D_CURDOT=0)then
												D_CURDOT<=15;
												vaddr:=vaddr-1;
											else
												D_CURDOT<=D_CURDOT-1;
											end if;
										when others =>
										end case;
									end if;
									D_CURADDR<=vaddr;
									GDC_ADDR<=vaddr;
									D_STATE<=DS_WRITEW;
								end if;
							end if;
						when DS_WRITEW =>
							if(GDC_MACK='0')then
								GDC_RD<='1';
								D_STATE<=DS_READ;
							end if;
						when others =>
							D_STATE<=DS_IDLE;
						end case;
					when DM_RECT =>
						case D_STATE is
						when DS_IDLE =>
							if(DRAW_BEGIN='1')then
								GDC_ADDR<=D_CURADDR;
								case D_DIR is
								when "000" =>
									D_STATE<=DS_READ;
								when "010" =>
									D_STATE<=DS_READ2;
								when "100" =>
									D_STATE<=DS_READ3;
								when "110" =>
									D_STATE<=DS_READ4;
								when others =>
									D_STATE<=DS_READ;
								end case;
								GDC_RD<='1';
								D_NUM<=D_D;
								mwait:=1;
							end if;
						when DS_READ =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<=D_PTN(i);
										when DW_XOR =>
											GDC_WDATx(i)<=D_PTN(i) xor GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<=GDC_RDATx(i) and (not D_PTN(i));
										when DW_OR =>
											GDC_WDATx(i)<=GDC_RDATx(i) or D_PTN(i);
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								D_STATE<=DS_READW;
							end if;
						when DS_READW =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								mwait:=1;
								D_STATE<=DS_WRITE;
							end if;
						when DS_WRITE =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								if(D_NUM=D_NUM1)then
									if(D_DIR="010" or D_DIR="011")then
										D_STATE<=DS_IDLE;
									else
										if(D_CURDOT=15)then
											D_CURADDR<=D_CURADDR+1;
											D_CURDOT<=0;
										else
											D_CURDOT<=D_CURDOT+1;
										end if;
										if(D_DIR(1)='0')then
											D_NUM<=D_D2;
										else
											D_NUM<=D_D;
										end if;
										D_STATE<=DS_WRITE2W;
									end if;
								else
									D_CURADDR<=D_CURADDR+r_PITCH(6 downto 0);
									D_STATE<=DS_WRITEW;
								end if;
							end if;
						when DS_WRITEW =>
							if(GDC_MACK='0')then
								GDC_RD<='1';
								D_STATE<=DS_READ;
							end if;
						when DS_READ2 =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<=D_PTN(i);
										when DW_XOR =>
											GDC_WDATx(i)<=D_PTN(i) xor GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<=GDC_RDATx(i) and (not D_PTN(i));
										when DW_OR =>
											GDC_WDATx(i)<=GDC_RDATx(i) or D_PTN(i);
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								D_STATE<=DS_READ2W;
							end if;
						when DS_READ2W =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								D_STATE<=DS_WRITE2;
							end if;
						when DS_WRITE2 =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								if(D_NUM=D_NUM1)then
									if(D_DIR="100" or D_DIR="101")then
										D_STATE<=DS_IDLE;
									else
										D_CURADDR<=D_CURADDR-r_PITCH(6 downto 0);
										if(D_DIR(1)='1')then
											D_NUM<=D_D2;
										else
											D_NUM<=D_D;
										end if;
										D_STATE<=DS_WRITE3W;
									end if;
								else
									if(D_CURDOT=15)then
										D_CURADDR<=D_CURADDR+1;
										D_CURDOT<=0;
									else
										D_CURDOT<=D_CURDOT+1;
									end if;
									D_STATE<=DS_WRITE2W;
								end if;
							end if;
						when DS_WRITE2W =>
							if(GDC_MACK='0')then
								GDC_RD<='1';
								D_STATE<=DS_READ2;
							end if;
						when DS_READ3 =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<=D_PTN(i);
										when DW_XOR =>
											GDC_WDATx(i)<=D_PTN(i) xor GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<=GDC_RDATx(i) and (not D_PTN(i));
										when DW_OR =>
											GDC_WDATx(i)<=GDC_RDATx(i) or D_PTN(i);
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								D_STATE<=DS_READ3W;
							end if;
						when DS_READ3W =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								D_STATE<=DS_WRITE3;
							end if;
						when DS_WRITE3 =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								if(D_NUM=D_NUM1)then
									if(D_DIR="110" or D_DIR="111")then
										D_STATE<=DS_IDLE;
									else
										if(D_CURDOT=0)then
											D_CURADDR<=D_CURADDR-1;
											D_CURDOT<=15;
										else
											D_CURDOT<=D_CURDOT-1;
										end if;
										if(D_DIR(1)='0')then
											D_NUM<=D_D2;
										else
											D_NUM<=D_D;
										end if;
										D_STATE<=DS_WRITE4W;
									end if;
								else
									D_CURADDR<=D_CURADDR-r_PITCH(6 downto 0);
									D_STATE<=DS_WRITE3W;
								end if;
							end if;
						when DS_WRITE3W =>
							if(GDC_MACK='0')then
								GDC_RD<='1';
								D_STATE<=DS_READ3;
							end if;
						when DS_READ4 =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<=D_PTN(i);
										when DW_XOR =>
											GDC_WDATx(i)<=D_PTN(i) xor GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<=GDC_RDATx(i) and (not D_PTN(i));
										when DW_OR =>
											GDC_WDATx(i)<=GDC_RDATx(i) or D_PTN(i);
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								D_STATE<=DS_READ4W;
							end if;
						when DS_READ4W =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								D_STATE<=DS_WRITE4;
							end if;
						when DS_WRITE4 =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								if(D_NUM=D_NUM1)then
									if(D_DIR="000" or D_DIR="001")then
										D_STATE<=DS_IDLE;
									else
										D_CURADDR<=D_CURADDR+r_PITCH(6 downto 0);
										if(D_DIR(1)='1')then
											D_NUM<=D_D2;
										else
											D_NUM<=D_D;
										end if;
										D_STATE<=DS_WRITE4W;
									end if;
								else
									if(D_CURDOT=0)then
										D_CURADDR<=D_CURADDR-1;
										D_CURDOT<=15;
									else
										D_CURDOT<=D_CURDOT-1;
									end if;
									D_STATE<=DS_WRITE4W;
								end if;
							end if;
						when DS_WRITE4W =>
							if(GDC_MACK='0')then
								GDC_RD<='1';
								D_STATE<=DS_READ4;
							end if;
						when others =>
						end case;
					
					when DM_CIRCLE =>
						case D_STATE is
						when DS_IDLE =>
							if(DRAW_BEGIN='1')then
								GDC_ADDR<=D_CURADDR;
								GDC_RD<='1';
								D_NUM<=(others=>'0');
								lasty<=D_D+1;
								circlecalc<='1';
								D_STATE<=DS_READ;
							end if;
						when DS_READ =>
							if(GDC_MACK='1')then
								for i in 0 to 15 loop
									if(i=D_CURDOT)then
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(i)<=D_PTN(i);
										when DW_XOR =>
											GDC_WDATx(i)<=D_PTN(i) xor GDC_RDATx(i);
										when DW_NAND =>
											GDC_WDATx(i)<=GDC_RDATx(i) and (not D_PTN(i));
										when DW_OR =>
											GDC_WDATx(i)<=GDC_RDATx(i) or D_PTN(i);
										when others =>
										end case;
									else
										GDC_WDATx(i)<=GDC_RDATx(i);
									end if;
								end loop;
								GDC_RD<='0';
								D_STATE<=DS_READW;
							end if;
						when DS_READW =>
							if(GDC_MACK='0')then
								if(D_NUM<D_DM)then
									D_STATE<=DS_WRITEW;
								elsif(D_NUM=D_DC+1)then
									D_STATE<=DS_IDLE;
								else
									GDC_WR<='1';
									D_STATE<=DS_WRITE;
								end if;
							end if;
						when DS_WRITE =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								D_STATE<=DS_WRITEW;
							end if;
						when DS_WRITEW =>
							if(GDC_MACK='0' and circlebusy='0')then
								vaddr:=D_CURADDR;
								case D_DIR is
								when "000" | "111" =>
									vaddr:=vaddr+r_PITCH(6 downto 0);
								when "001" | "010" =>
									if(D_CURDOT=15)then
										vaddr:=vaddr+1;
										D_CURDOT<=0;
									else
										D_CURDOT<=D_CURDOT+1;
									end if;
								when "011" | "100" =>
									vaddr:=vaddr-r_PITCH(6 downto 0);
								when "101" | "110" =>
									if(D_CURDOT=0)then
										vaddr:=vaddr-1;
										D_CURDOT<=15;
									else
										D_CURDOT<=D_CURDOT-1;
									end if;
								when others =>
								end case;
								if(circleY/=lastY)then
									case D_DIR is
									when "000" | "011" =>
										if(D_CURDOT=15)then
											vaddr:=vaddr+1;
											D_CURDOT<=0;
										else
											D_CURDOT<=D_CURDOT+1;
										end if;
									when "001" | "110" =>
										vaddr:=vaddr+r_PITCH(6 downto 0);
									when "010" | "101" =>
										vaddr:=vaddr-r_PITCH(6 downto 0);
									when "100" | "111" =>
										if(D_CURDOT=0)then
											vaddr:=vaddr-1;
											D_CURDOT<=15;
										else
											D_CURDOT<=D_CURDOT-1;
										end if;
									when others =>
									end case;
								end if;
								lastY<=circleY;
								D_CURADDR<=vaddr;
								GDC_ADDR<=vaddr;
								GDC_RD<='1';
								D_NUM<=D_NUM+1;
								circlecalc<='1';
								D_STATE<=DS_READ;
							end if;
						when others =>
							D_STATE<=DS_IDLE;
						end case;
					when others =>
					end case;
				when DO_READ =>
					if(DRAW_BEGIN='1')then
						GDC_ADDR<=D_CURADDR;
						GDC_RD<='1';
						mwait:=1;
						D_STATE<=DS_READ;
					else
						case D_STATE is
						when DS_READ =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								GDC_WDATx<=GDC_RDATx;
								D_STATE<=DS_READW;
							end if;
						when DS_READW =>
							if(GDC_MACK='0')then
								D_RDDONE<='1';
								D_STATE<=DS_IDLE;
								D_CURADDR<=D_CURADDR+1;
							end if;
						when others =>
						end case;
					end if;
				when DO_WRITE =>
					if(DRAW_BEGIN='1')then
						GDC_ADDR<=D_CURADDR;
						GDC_RD<='1';
						mwait:=1;
						D_STATE<=DS_READ;
					else
						case D_STATE is
						when DS_READ =>
							if(GDC_MACK='1')then
								GDC_RD<='0';
								case COMMAND is
								when x"20" | x"21" | x"22" | x"23" =>
									if((PARNUM mod 2)=0)then
										GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8);
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(7 downto 0)<=D_WRDAT;
										when DW_XOR =>
											GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0) xor D_WRDAT;
										when DW_NAND =>
											GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0) and (not D_WRDAT);
										when DW_OR =>
											GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0) or D_WRDAT;
										when others =>
										end case;
									else
										GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0);
										case D_WRMODE is
										when DW_SET =>
											GDC_WDATx(15 downto 8)<=D_WRDAT;
										when DW_XOR =>
											GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8) xor D_WRDAT;
										when DW_NAND =>
											GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8) and (not D_WRDAT);
										when DW_OR =>
											GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8) or D_WRDAT;
										when others =>
										end case;
									end if;
								when x"30" | x"31" | x"32" | x"33" =>
									GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8);
									case D_WRMODE is
									when DW_SET =>
										GDC_WDATx(7 downto 0)<=D_WRDAT;
									when DW_XOR =>
										GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0) xor D_WRDAT;
									when DW_NAND =>
										GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0) and (not D_WRDAT);
									when DW_OR =>
										GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0) or D_WRDAT;
									when others =>
									end case;
								when x"38" | x"39" | x"3a" | x"3b" =>
									GDC_WDATx(7 downto 0)<=GDC_RDATx(7 downto 0);
									case D_WRMODE is
									when DW_SET =>
										GDC_WDATx(15 downto 8)<=D_WRDAT;
									when DW_XOR =>
										GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8) xor D_WRDAT;
									when DW_NAND =>
										GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8) and (not D_WRDAT);
									when DW_OR =>
										GDC_WDATx(15 downto 8)<=GDC_RDATx(15 downto 8) or D_WRDAT;
									when others =>
									end case;
								when others =>
								end case;
								D_STATE<=DS_READW;
							end if;
						when DS_READW =>
							if(GDC_MACK='0')then
								GDC_WR<='1';
								D_STATE<=DS_WRITE;
							end if;
						when DS_WRITE =>
							if(GDC_MACK='1')then
								GDC_WR<='0';
								D_STATE<=DS_WRITEW;
							end if;
						when DS_WRITEW =>
							if(GDC_MACK='0')then
								case COMMAND is
								when x"20" | x"21" | x"22" | x"23" =>
									if((PARNUM mod 2)=1)then
										D_CURADDR<=D_CURADDR+1;
									end if;
								when others =>
									D_CURADDR<=D_CURADDR+1;
								end case;
								D_STATE<=DS_IDLE;
							end if;
						when others =>
						end case;
					end if;
				when others =>
				end case;
			end if;
		end if;
	end process;
	
	GDC_WDAT<=GDC_WDATx(8) & GDC_WDATx(9) & GDC_WDATx(10) & GDC_WDATx(11) & GDC_WDATx(12) & GDC_WDATx(13) & GDC_WDATx(14) & GDC_WDATx(15) & GDC_WDATx(0) & GDC_WDATx(1) & GDC_WDATx(2) & GDC_WDATx(3) & GDC_WDATx(4) & GDC_WDATx(5) & GDC_WDATx(6) & GDC_WDATx(7);

	ccalc	:calccircle generic map(14) port map(
		r		=>D_D+1,
		x		=>D_NUM,
		calc	=>circlecalc,
		
		y		=>circleY,
		busy	=>circlebusy,
		done	=>open,
		
		clk		=>clk,
		rstn	=>rstn
	);
	
end rtl;
