LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity TXTGDC is
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
	-- Active display from RESET/SYNC: AW-2 words (P2) and AL lines (P7/P8).
	-- The text GDC is the display master; The Return of Ishtar sets 72x384.
	DISPAW		:out std_logic_vector(7 downto 0);
	DISPAL		:out std_logic_vector(9 downto 0);

	clk		:in std_logic;
	rstn	:in std_logic
);
end TXTGDC;

architecture rtl of TXTGDC is

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

signal	RFIFOADDR	:std_logic_vector(3 downto 0);
signal	WNFIFOADDR	:std_logic_vector(3 downto 0);
signal	WFIFOADDR	:std_logic_vector(3 downto 0);
signal	STATUS		:std_logic_vector(7 downto 0);
signal	RDATA		:std_logic_vector(7 downto 0);
signal	sDMAEXEC	:std_logic;
signal	sDRAWING	:std_logic;
signal	sFIFOE		:std_logic;
signal	sFIFOF		:std_logic;
signal	sDREADY		:std_logic;

signal	mWR,lWR			:std_logic;
signal	FIFOWDAT,FIFORDAT	:std_logic_vector(8 downto 0);
signal	FIFOWR		:std_logic;

signal	r_ATRSEL	:std_logic;
signal	r_C40		:std_logic;
signal	r_GRMONO	:std_logic;
signal	r_FONTSEL	:std_logic;
signal	r_GRPMODE	:std_logic;
signal	r_KACMODE	:std_logic;
signal	r_NVMWPROT	:std_logic;
signal	r_DISPEN	:std_logic;
signal	r_COLORMODE	:std_logic;
signal	r_EGCEN		:std_logic;
signal	r_EGCPROT	:std_logic;
signal	r_GDCCLK	:std_logic;
signal	r_GDCCLK2	:std_logic;
signal	r_EAD		:std_logic_vector(12 downto 0);
signal	MODEREG1,MODEREG2	:std_logic_vector(7 downto 0);
signal	COMMAND		:std_logic_vector(7 downto 0);
signal	PARNUM		:integer range 0 to 15;
signal	gdcreset	:std_logic;
signal	fifoexist	:std_logic;
signal	RDNUM		:integer range 0 to 15;
signal	RNUMCLR		:std_logic;
signal	DATRD		:std_logic;
signal	RDEXIST	:std_logic;
signal	NUMRDAT	:integer range 0 to 15;
signal	INTER	:std_logic;


begin

	STATUS<=LPEND & HRTC & VRTC & sDMAEXEC & sDRAWING & sFIFOE & sFIFOF & sDREADY;
	sDMAEXEC<='0';
	sDRAWING<='0';
	sFIFOE<=	'1' when RFIFOADDR=WNFIFOADDR else '0';
	sFIFOF<=	'1' when (WNFIFOADDR+"0001")=RFIFOADDR else '0';
	fifoexist<=	'0' when RFIFOADDR=WNFIFOADDR else '1';
	sDREADY<=RDEXIST;

	mWR<='1' when WR='1' and CS='1' and ADDR(2 downto 1)="00" else '0';
	
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
	
	DOUT<=	STATUS 	when ADDR="000" else
			RDATA	when ADDR="001" else
			MODEREG1 when ADDR="100" else
			MODEREG2 when ADDR="101" else
			(others=>'0');
	
	RDATA<=	r_EAD(7 downto 0)			when COMMAND=x"e0" and RDNUM=0 else
			"000" & r_EAD(12 downto 8)	when COMMAND=x"e0" and RDNUM=1 else
			(others=>'0');
	
	DOE<=	'1' when CS='1' and RD='1' else
			'0';
	
	FIFO	:gdcfifo port map(clk,FIFOWDAT,RFIFOADDR,WFIFOADDR,FIFOWR,FIFORDAT);
	
	--dummy GDC processor
	process(clk,rstn)
	begin
		if(rstn='0')then
			RFIFOADDR<=(others=>'1');
			PARNUM<=0;
			COMMAND<=(others=>'0');
			CUREN<='0';
			CHARLINES<=(others=>'0');
			BLRATE<=(others=>'0');
			CURBLINK<='0';
			CURUPPER<=(others=>'0');
			CURLOWER<=(others=>'0');
			gdcreset<='0';
			VIDEN<='0';
			SAD0<=(others=>'0');
			SAD1<=(others=>'0');
			SAD2<=(others=>'0');
			SAD3<=(others=>'0');
			SL0<=(others=>'0');
			SL1	<=(others=>'0');
			SL2	<=(others=>'0');
			SL3<=(others=>'0');
			PITCH<=(others=>'0');
			r_EAD<=(others=>'0');
			RNUMCLR<='0';
			NUMRDAT<=0;
			DISPAW<=x"4e";						-- 80 words
			DISPAL<="0110010000";				-- 400 lines
		elsif(clk' event and clk='1')then
			gdcreset<='0';
			RNUMCLR<='0';
			if(gdcreset='1')then
				RFIFOADDR<=(others=>'0');
				PARNUM<=0;
				COMMAND<=(others=>'0');
				CUREN<='0';
				CHARLINES<=(others=>'0');
				BLRATE<=(others=>'0');
				CURBLINK<='0';
				CURUPPER<=(others=>'0');
				CURLOWER<=(others=>'0');
				VIDEN<='0';
				SAD0<=(others=>'0');
				SAD1<=(others=>'0');
				SAD2<=(others=>'0');
				SAD3<=(others=>'0');
				SL0<=(others=>'0');
				SL1	<=(others=>'0');
				SL2	<=(others=>'0');
				SL3<=(others=>'0');
				PITCH<=(others=>'0');
				r_EAD<=(others=>'0');
				NUMRDAT<=0;
			elsif(fifoexist='1')then
				if(FIFORDAT(8)='1')then		--command
					NUMRDAT<=0;
					COMMAND<=FIFORDAT(7 downto 0);
					PARNUM<=0;
					RNUMCLR<='1';
					case FIFORDAT(7 downto 0) is
					when x"00" =>	--RESET1
						gdcreset<='1';
					when x"6b" |x"0d" =>	--start
						VIDEN<='1';
					when x"0c" =>
						VIDEN<='0';
					when x"e0" =>	-- CSRR takes no parameters; its 5 bytes are ready at once
						NUMRDAT<=5;
					when x"70" | x"71" | x"72" | x"73" |
						 x"74" | x"75" | x"76" | x"77" |
						 x"78" | x"79" | x"7a" | x"7b" |
						 x"7c" | x"7d" | x"7e" | x"7f" =>
						 PARNUM<=conv_integer(FIFORDAT(3 downto 0));
					when others =>
					end case;
				else
					case COMMAND is
					when x"0e" | x"0f" | x"00" =>	-- SYNC, and RESET's same parameters
						case PARNUM is
						when 0 =>
							INTER<=FIFORDAT(3);
						when 1 =>
							DISPAW<=FIFORDAT(7 downto 0);
						when 6 =>
							DISPAL(7 downto 0)<=FIFORDAT(7 downto 0);
						when 7 =>
							DISPAL(9 downto 8)<=FIFORDAT(1 downto 0);
						when others =>
						end case;
					when x"4b" =>
						case PARNUM is
						when 0 =>
							CUREN<=FIFORDAT(7);
							CHARLINES<=FIFORDAT(4 downto 0);
						when 1 =>
							BLRATE(1 downto 0)<=FIFORDAT(7 downto 6);
							CURBLINK<=FIFORDAT(5);
							CURUPPER<=FIFORDAT(4 downto 0);
						when 2 =>
							CURLOWER<=FIFORDAT(7 downto 3);
							BLRATE(4 downto 2)<=FIFORDAT(2 downto 0);
						when others =>
						end case;
					when x"70" | x"71" | x"72" | x"73" |
						 x"74" | x"75" | x"76" | x"77" |
						 x"78" | x"79" | x"7a" | x"7b" |
						 x"7c" | x"7d" | x"7e" | x"7f" =>
						case PARNUM is
						when 0 =>
							SAD0(7 downto 0)<=FIFORDAT(7 downto 0);
						when 1 =>
							SAD0(12 downto 8)<=FIFORDAT(4 downto 0);
						when 2 =>
							SL0(3 downto 0)<=FIFORDAT(7 downto 4);
						when 3 =>
							SL0(9 downto 4)<=FIFORDAT(5 downto 0);
						when 4 =>
							SAD1(7 downto 0)<=FIFORDAT(7 downto 0);
						when 5 =>
							SAD1(12 downto 8)<=FIFORDAT(4 downto 0);
						when 6 =>
							SL1(3 downto 0)<=FIFORDAT(7 downto 4);
						when 7 =>
							SL1(9 downto 4)<=FIFORDAT(5 downto 0);
						when 8 =>
							SAD2(7 downto 0)<=FIFORDAT(7 downto 0);
						when 9 =>
							SAD2(12 downto 8)<=FIFORDAT(4 downto 0);
						when 10 =>
							SL2(3 downto 0)<=FIFORDAT(7 downto 4);
						when 11 =>
							SL2(9 downto 4)<=FIFORDAT(5 downto 0);
						when 12 =>
							SAD3(7 downto 0)<=FIFORDAT(7 downto 0);
						when 13 =>
							SAD3(12 downto 8)<=FIFORDAT(4 downto 0);
						when 14 =>
							SL3(3 downto 0)<=FIFORDAT(7 downto 4);
						when 15 =>
							SL3(9 downto 4)<=FIFORDAT(5 downto 0);
						when others =>
						end case;
					when x"47" =>
						PITCH<=FIFORDAT(7 downto 0);
					when x"49" =>
						case PARNUM is
						when 0 =>
							r_EAD(7 downto 0)<=FIFORDAT(7 downto 0);
						when 1 =>
							r_EAD(12 downto 8)<=FIFORDAT(4 downto 0);
						when others =>
						end case;
					when others =>
					end case;
					PARNUM<=PARNUM+1;
				end if;
				RFIFOADDR<=RFIFOADDR+x"1";
			end if;
		end if;
	end process;
	
	process(clk,rstn)begin
		if(rstn='0')then
			r_ATRSEL	<='0';
			r_C40		<='0';
			r_GRMONO	<='0';
			r_FONTSEL	<='0';
			r_GRPMODE	<='0';
			r_KACMODE	<='0';
			r_NVMWPROT	<='0';
			r_DISPEN	<='0';
			r_COLORMODE	<='0';
			r_EGCEN		<='0';
			r_EGCPROT	<='0';
			r_GDCCLK	<='0';
			r_GDCCLK2	<='0';
		elsif(clk' event and clk='1')then
			if(gdcreset='1')then
				r_ATRSEL	<='0';
				r_C40		<='0';
				r_GRMONO	<='0';
				r_FONTSEL	<='0';
				r_GRPMODE	<='0';
				r_KACMODE	<='0';
				r_NVMWPROT	<='0';
				r_DISPEN	<='0';
				r_COLORMODE	<='0';
				r_EGCEN		<='0';
				r_EGCPROT	<='0';
				r_GDCCLK	<='0';
				r_GDCCLK2	<='0';
			elsif(CS='1' and WR='1')then
				case ADDR is
				when "100" =>
					case DIN(7 downto 1) is
					when "0000000" =>
						r_ATRSEL<=DIN(0);
					when "0000001" =>
						r_GRMONO<=DIN(0);
					when "0000010" =>
						r_C40<=DIN(0);
					when "0000011" =>
						r_FONTSEL<=DIN(0);
					when "0000100" =>
						r_GRPMODE<=DIN(0);
					when "0000101" =>
						r_KACMODE<=DIN(0);
					when "0000110" =>
						r_NVMWPROT<=DIN(0);
					when "0000111" =>
						r_DISPEN<=DIN(0);
					when others =>
					end case;
				when "101" =>
					case DIN(7 downto 1) is
					when "0000000" =>
						r_COLORMODE<=DIN(0);
					when "0000010" =>
						if(r_EGCPROT='1')then
							r_EGCEN<=DIN(0);
						end if;
					when "0000011" =>
						r_EGCPROT<=DIN(0);
					when "1000001" =>
						r_GDCCLK<=DIN(0);
					when "1000010" =>
						r_GDCCLK2<=DIN(0);
					when others =>
					end case;
				when others =>
				end case;
			end if;
		end if;
	end process;

	ATRSEL<=	r_ATRSEL;
	C40<=		r_C40;
	GRMONO<=	r_GRMONO;
	FONTSEL<=	r_FONTSEL;
	GRPMODE<=	r_GRPMODE;
	KACMODE<=	r_KACMODE;
	NVMWPROT<=	r_NVMWPROT;
	DISPEN<=	r_DISPEN;
	COLORMODE<=	r_COLORMODE;
	EGCEN<=		r_EGCEN;
	GDCCLK<=	r_GDCCLK;
	GDCCLK2<=	r_GDCCLK2;
	EAD<=		r_EAD;
	MODEREG1<=r_KACMODE & r_NVMWPROT & "00" & r_C40 & r_GRMONO & '0' & r_ATRSEL;
	MODEREG2<=(others=>'0');
	
	DATRD<='1' when CS='1' and ADDR="001" and RD='1' else '0';
	
	process(clk,rstn)
	variable lRD	:std_logic;
	begin
		if(rstn='0')then
			RDNUM<=0;
			lRD:='0';
		elsif(clk' event and clk='1')then
			if(RNUMCLR='1')then
				RDNUM<=0;
			elsif(lRD='1' and DATRD='0')then
				RDNUM<=RDNUM+1;
			end if;
			lRD:=DATRD;
		end if;
	end process;
	
	RDEXIST<='1' when NUMRDAT>RDNUM else '0';

end rtl;
