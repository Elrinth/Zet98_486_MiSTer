LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.VIDEO_TIMING_pkg.all;

entity CRTC98 is
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
end CRTC98;

architecture MAIN of CRTC98 is
component VTIMING is
generic(
	DOTPU	:integer	:=8;
	HWIDTH	:integer	:=800;
	VWIDTH	:integer	:=525;
	HVIS	:integer	:=640;
	VVIS	:integer	:=400;
	CPD		:integer	:=3;		--clocks per dot
	HFP		:integer	:=3;
	HSY		:integer	:=12;
	VFP		:integer	:=51;
	VSY		:integer	:=2
);	
port(
	VCOUNT	:out integer range 0 to VWIDTH-1;
	HUCOUNT	:out integer range 0 to (HWIDTH/DOTPU)-1;
	UCOUNT	:out integer range 0 to DOTPU-1;
	
	HCOMP	:out std_logic;
	VCOMP	:out std_logic;
	
	clk2	:out std_logic;
	clk3	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component KNJSCR
generic(
	BLINKINT :integer	:=40
);
port(
	TRAMADR	:out std_logic_vector(12 downto 0);
	TRAMDAT	:in std_logic_vector(15 downto 0);
	TRAMATR	:in std_logic_vector(7 downto 0);
	
	FROMSEL	:out std_logic_vector(1 downto 0);
	FROMADR:out std_logic_vector(16 downto 0);
	FROMDAT:in std_logic_vector(7 downto 0)	:=x"00";
	
	BITOUT	:out std_logic;
	COLOR	:out std_logic_vector(2 downto 0);
	
	CURADDR	:in std_logic_vector(12 downto 0);
	CURE	:in std_logic;
	CURUPPER:in integer range 0 to 19;
	CURLOWER:in integer range 0 to 19;
	CBLINK	:in std_logic;
	BLINKRATE:in std_logic_vector(4 downto 0);
	
	BASEADDR:in std_logic_vector(12 downto 0);
	HMODE	:in std_logic;
	VLINES	:in std_logic_vector(4 downto 0);
	PITCH	:in std_logic_vector(7 downto 0);
	
	UCOUNT	:in integer range 0 to DOTPU-1;
	HUCOUNT	:in integer range 0 to (HWIDTH/DOTPU)-1;
	VCOUNT	:in integer range 0 to VWIDTH-1;
	HCOMP	:in std_logic;
	VCOMP	:in std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component GRAPHSCR98
port(
	GRAMADR	:out std_logic_vector(13 downto 0);
	GRAMRD	:out std_logic;
	GRAMACK:in std_logic;
	GRAMDAT0:in std_logic_vector(15 downto 0);
	GRAMDAT1:in std_logic_vector(15 downto 0);
	GRAMDAT2:in std_logic_vector(15 downto 0);
	GRAMDAT3:in std_logic_vector(15 downto 0);

	DOTOUT	:out std_logic_vector(3 downto 0);
	DOTE	:out std_logic;

	GRAPHEN	:in std_logic;
	DOTPLINE:in std_logic_vector(4 downto 0);
	BLANK	:in std_logic;
	
	UCOUNT	:in integer range 0 to DOTPU-1;
	HUCOUNT	:in integer range 0 to (HWIDTH/DOTPU)-1;
	VCOUNT	:in integer range 0 to VWIDTH-1;
	HCOMP	:in std_logic;
	VCOMP	:in std_logic;

	BASEADDR0	:in std_logic_vector(13 downto 0);
	BASEADDR1	:in std_logic_vector(13 downto 0);
	LINENUM0	:in std_logic_vector(9 downto 0);
	LINENUM1	:in std_logic_vector(9 downto 0);
	PITCH	:in std_logic_vector(7 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component synccont2
generic(
	DOTPU	:integer	:=8;
	HWIDTH	:integer	:=800;
	VWIDTH	:integer	:=525;
	HVIS	:integer	:=640;
	VVIS	:integer	:=400;
	VVIS2	:integer	:=480;
	CPD		:integer	:=3;		--clocks per dot
	HFP		:integer	:=3;
	HSY		:integer	:=12;
	VFP		:integer	:=51;
	VSY		:integer	:=2
);	
port(
	UCOUNT	:in integer range 0 to DOTPU-1;
	HUCOUNT	:in integer range 0 to (HWIDTH/DOTPU)-1;
	VCOUNT	:in integer range 0 to VWIDTH-1;
	HCOMP	:in std_logic;
	VCOMP	:in std_logic;

	HSYNC	:out std_logic;
	VSYNC	:out std_logic;
	VISIBLE	:out std_logic;
	VIDEN		:out std_logic;
	
	HRTC	:out std_logic;
	VRTC	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

component TEXTSCR
generic(
	CURLINE	:integer	:=4;
	CBLINKINT :integer	:=20;
	BLINKINT :integer	:=40
);
port(
	TRAMADR	:out std_logic_vector(11 downto 0);
	TRAMDAT	:in std_logic_vector(7 downto 0);
	
	FRAMADR	:out std_logic_vector(11 downto 0);
	FRAMDAT	:in std_logic_vector( 7 downto 0);
	
	BITOUT	:out std_logic;
	FGCOLOR	:out std_logic_vector(2 downto 0);
	BGCOLOR	:out std_logic_vector(2 downto 0);
	THRUE	:out std_logic;
	BLINK	:out std_logic;
	
	CURL	:in std_logic_vector(4 downto 0);
	CURC	:in std_logic_vector(6 downto 0);
	CURE	:in std_logic;
	CURM	:in std_logic;
	CBLINK	:in std_logic;
	
	HMODE	:in std_logic;
	VMODE	:in std_logic;
	
	UCOUNT	:in integer range 0 to DOTPU-1;
	HUCOUNT	:in integer range 0 to (HWIDTH/DOTPU)-1;
	VCOUNT	:in integer range 0 to VWIDTH-1;
	HCOMP	:in std_logic;
	VCOMP	:in std_logic;

	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

signal VCOUNT	:integer range 0 to VWIDTH-1;
signal HUCOUNT	:integer range 0 to (HWIDTH/DOTPU)-1;
signal UCOUNT	:integer range 0 to DOTPU-1;
signal HCOMP	:std_logic;
signal VCOMP	:std_logic;
signal VISIBLE	:std_logic;
signal GRPHR		:std_logic_vector(3 downto 0);
signal GRPHG		:std_logic_vector(3 downto 0);
signal GRPHB		:std_logic_vector(3 downto 0);
	
signal clk2		:std_logic;
signal clk3		:std_logic;
signal pixel_rstn :std_logic;

signal TCOLOR	:std_logic_vector(2 downto 0);
signal T_BIT	:std_logic;
signal ET_BIT	:std_logic;
signal EF_COLOR	:std_logic_vector(2 downto 0);
signal EB_COLOR	:std_logic_vector(2 downto 0);

signal G_DOT	:std_logic_vector(3 downto 0);
signal G_DOTE	:std_logic;

signal EFNT_ADDR	:std_logic_vector(11 downto 0);
signal KNJFNT_ADDR	:std_logic_vector(16 downto 0);
signal KNJFNT_SEL		:std_logic_vector(1 downto 0);
signal ETRAM_ADRX	:std_logic_Vector(11 downto 0);

begin
	TIM	:vtiming generic map(
	DOTPU	=>DOTPU,
	HWIDTH	=>HWIDTH,
	VWIDTH	=>VWIDTH,
	HVIS	=>HVIS,
	VVIS	=>VVIS,
	CPD		=>CPD,
	HFP		=>HFP,
	HSY		=>HSY,
	VFP		=>VFP,
	VSY		=>VSY
	) port map(VCOUNT,HUCOUNT,UCOUNT,HCOMP,VCOMP,clk2,clk3,clk,rstn);
	
	KNJSEL	<=KNJFNT_SEL when EMUMODE='0' else "00";
	KNJADR	<=KNJFNT_ADDR when EMUMODE='0' else ('0' & x"0800")+EFNT_ADDR;
	
	pixel_reset : entity work.reset_release port map(clk3,rstn,pixel_rstn);

	TXT	:knjscr port map(
		TRAMADR	=>TRAM_ADR,
		TRAMDAT	=>TRAM_DAT,
		TRAMATR	=>TRAM_ATR,
		
		FROMSEL	=>KNJFNT_SEL,
		FROMADR	=>KNJFNT_ADDR,
		FROMDAT	=>KNJDAT,
		
		BITOUT	=>T_BIT,
		COLOR	=>TCOLOR,
		
		CURADDR	=>CURADDR,
		CURE	=>CURE,
		CURUPPER=>CURUPPER,
		CURLOWER=>CURLOWER,
		CBLINK	=>CBLINK,
		BLINKRATE=>BLINKRATE,
		
		BASEADDR=>TBASEADDR,
		HMODE	=>HMODE,
		VLINES	=>VLINES,
		PITCH	=>TPITCH,
		
		UCOUNT	=>UCOUNT,
		HUCOUNT	=>HUCOUNT,
		VCOUNT	=>VCOUNT,
		HCOMP	=>HCOMP,
		VCOMP	=>VCOMP,

		clk		=>clk3,
		rstn	=>pixel_rstn
	);
	
	ETXT	:TEXTSCR generic map(4,20,40) port map(
		TRAMADR	=>ETRAM_ADRx,
		TRAMDAT	=>ETRAM_DAT,
		
		FRAMADR	=>EFNT_ADDR,
		FRAMDAT	=>KNJDAT,
		
		BITOUT	=>ET_BIT,
		FGCOLOR	=>EF_COLOR,
		BGCOLOR	=>EB_COLOR,
		THRUE		=>open,
		BLINK		=>open,
		
		CURL		=>ECURL,
		CURC		=>ECURC,
		CURE		=>ECUREN,
		CURM		=>'0',
		CBLINK	=>'1',
		
		HMODE		=>'1',
		VMODE		=>'1',
		
		UCOUNT	=>UCOUNT,
		HUCOUNT	=>HUCOUNT,
		VCOUNT	=>VCOUNT,
		HCOMP		=>HCOMP,
		VCOMP		=>VCOMP,

		clk		=>clk3,
		rstn		=>pixel_rstn
	);
	ETRAM_ADR<=ETRAM_ADRX(0) & ETRAM_ADRX(11 downto 1);
	
	
	GRP:GRAPHSCR98 port map(
		GRAMADR	=>GRAMADR,
		GRAMRD	=>GRAMRD,
		GRAMACK	=>GRAMACK,
		GRAMDAT0=>GRAMDAT0,
		GRAMDAT1=>GRAMDAT1,
		GRAMDAT2=>GRAMDAT2,
		GRAMDAT3=>GRAMDAT3,

		DOTOUT	=>G_DOT,
		DOTE	=>G_DOTE,

		GRAPHEN	=>GRAPHEN,
		DOTPLINE=>DOTPLINE,
		BLANK	=>LOWBL,
		
		UCOUNT	=>UCOUNT,
		HUCOUNT	=>HUCOUNT,
		VCOUNT	=>VCOUNT,
		HCOMP	=>HCOMP,
		VCOMP	=>VCOMP,

		BASEADDR0=>GBASEADDR0,
		BASEADDR1=>GBASEADDR1,
		LINENUM0=>GLINENUM0,
		LINENUM1=>GLINENUM1,
		PITCH	=>GPITCH,
		
		clk		=>clk3,
		rstn	=>pixel_rstn
	);

	sync:synccont2 generic map(
	DOTPU	=>DOTPU,
	HWIDTH	=>HWIDTH,
	VWIDTH	=>VWIDTH,
	HVIS	=>HVIS,
	VVIS	=>VVIS,
	VVIS2	=>VVIS2,
	CPD		=>CPD,
	HFP		=>HFP,
	HSY		=>HSY,
	VFP		=>VFP,
	VSY		=>VSY
) port map(UCOUNT,HUCOUNT,VCOUNT,HCOMP,VCOMP,HSYNC,VSYNC,VISIBLE,open,HRTC,VRTC,clk3,pixel_rstn);
	-- RGB is already forced black outside VISIBLE (640x400). Capturing 480
	-- lines included an 80-line black border and distorted HDMI aspect/scaling.
	-- Use the same delayed visible window for DE; HS/VS and RGB do not change.
	VIDEOEN<=VISIBLE;

	GRPHB<=	x"0" when GRAPHEN='0' else
				x"0" when G_DOTE='0' else
				GPALB;

	GRPHR<=	x"0" when GRAPHEN='0' else
				x"0" when G_DOTE='0' else
				GPALR;

	GRPHG<=	x"0" when GRAPHEN='0' else
				x"0" when G_DOTE='0' else
				GPALG;

	GPALNO<=G_DOT;

	BOUT<="0000" when VISIBLE='0' else 
			(others=>EF_COLOR(0)) when EMUMODE='1' and ET_BIT='1' else
			(others=>EB_COLOR(0)) when EMUMODE='1' and ET_BIT='0' else
			"1111" when TCOLOR(0)='1' and T_BIT='1' and TXTEN='1' else 
			"0000" when T_BIT='1' and TXTEN='1' else 
			GRPHB;
	ROUT<="0000" when VISIBLE='0' else 
			(others=>EF_COLOR(2)) when EMUMODE='1' and ET_BIT='1' else
			(others=>EB_COLOR(2)) when EMUMODE='1' and ET_BIT='0' else
			"1111" when TCOLOR(1)='1' and T_BIT='1' and TXTEN='1' else 
			"0000" when T_BIT='1' and TXTEN='1' else 
			GRPHR;
	GOUT<="0000" when VISIBLE='0' else 
			(others=>EF_COLOR(1)) when EMUMODE='1' and ET_BIT='1' else
			(others=>EB_COLOR(1)) when EMUMODE='1' and ET_BIT='0' else
			"1111" when TCOLOR(2)='1' and T_BIT='1' and TXTEN='1' else 
			"0000" when T_BIT='1' and TXTEN='1' else 
			GRPHG;

	gclk<=clk3;

end MAIN;
