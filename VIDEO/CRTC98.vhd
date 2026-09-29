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
	GBASEADDR2	:in std_logic_vector(13 downto 0);
	GBASEADDR3	:in std_logic_vector(13 downto 0);
	GLINENUM2	:in std_logic_vector(9 downto 0);
	GLINENUM3	:in std_logic_vector(9 downto 0);
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
	rstn		:in std_logic;
    ATRSEL :in std_logic := '0';
    PC_MODE,PC_SINGLE,PC_PAGE,PC_FAST,PC_B0HI,PC_B1HI :in std_logic := '0';
    PC_RGB :in std_logic_vector(23 downto 0) := (others=>'0');
    PC_VALID :in std_logic := '0';
    PC_LINE_START,PC_LINE_ENABLE,PC_ACTIVE,PC_PAGE_WRAP,PC_RSTN :out std_logic;
    PC_LINE_ADDRESS :out std_logic_vector(18 downto 3);
    PC_X :out std_logic_vector(9 downto 0);
    ROUT8,GOUT8,BOUT8 :out std_logic_vector(7 downto 0)
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
	VSY		:integer	:=2;
    EXTERNAL_PIXEL_RESET : boolean := false
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
	rstn	:in std_logic;
    pixel_rstn :in std_logic := '0'
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
	rstn	:in std_logic;
    ATRSEL :in std_logic := '0'
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
	BASEADDR2	:in std_logic_vector(13 downto 0);
	BASEADDR3	:in std_logic_vector(13 downto 0);
	LINENUM2	:in std_logic_vector(9 downto 0);
	LINENUM3	:in std_logic_vector(9 downto 0);
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

-- Stage GDC settings on the parent video clock before the pixel registers.
signal tbaseaddr_video : std_logic_vector(12 downto 0);
signal tpitch_video : std_logic_vector(7 downto 0);
signal atrsel_video, atrsel_pixel_source :std_logic;
signal hmode_video : std_logic;
signal vlines_video : std_logic_vector(4 downto 0);
signal curaddr_video : std_logic_vector(12 downto 0);
signal cure_video : std_logic;
signal curupper_video : integer range 0 to 19;
signal curlower_video : integer range 0 to 19;
signal cblink_video : std_logic;
signal blinkrate_video : std_logic_vector(4 downto 0);
signal gbaseaddr0_video : std_logic_vector(13 downto 0);
signal gbaseaddr1_video : std_logic_vector(13 downto 0);
signal glinenum0_video : std_logic_vector(9 downto 0);
signal glinenum1_video : std_logic_vector(9 downto 0);
signal gbaseaddr2_video, gbaseaddr3_video : std_logic_vector(13 downto 0);
signal glinenum2_video, glinenum3_video : std_logic_vector(9 downto 0);
signal gpitch_video : std_logic_vector(7 downto 0);
signal dotpline_video : std_logic_vector(4 downto 0);
signal graphen_video : std_logic;
signal lowbl_video : std_logic;

signal tbaseaddr_pixel_source : std_logic_vector(12 downto 0);
signal tpitch_pixel_source : std_logic_vector(7 downto 0);
signal hmode_pixel_source : std_logic;
signal vlines_pixel_source : std_logic_vector(4 downto 0);
signal curaddr_pixel_source : std_logic_vector(12 downto 0);
signal cure_pixel_source : std_logic;
signal curupper_pixel_source : integer range 0 to 19;
signal curlower_pixel_source : integer range 0 to 19;
signal cblink_pixel_source : std_logic;
signal blinkrate_pixel_source : std_logic_vector(4 downto 0);
signal gbaseaddr0_pixel_source : std_logic_vector(13 downto 0);
signal gbaseaddr1_pixel_source : std_logic_vector(13 downto 0);
signal glinenum0_pixel_source : std_logic_vector(9 downto 0);
signal glinenum1_pixel_source : std_logic_vector(9 downto 0);
signal gbaseaddr2_pixel_source, gbaseaddr3_pixel_source : std_logic_vector(13 downto 0);
signal glinenum2_pixel_source, glinenum3_pixel_source : std_logic_vector(9 downto 0);
signal gpitch_pixel_source : std_logic_vector(7 downto 0);
signal dotpline_pixel_source : std_logic_vector(4 downto 0);
signal graphen_pixel_source : std_logic;
signal txten_video : std_logic;
signal lowbl_pixel_source : std_logic;
signal pc_video,pc_pixel_source :std_logic_vector(5 downto 0);
signal pc_mode_pixel :std_logic;
signal pc_mode_delay :std_logic_vector(8 downto 0);
signal pc_valid_delay :std_logic_vector(6 downto 0);
type pc_rgb_array is array(0 to 5) of std_logic_vector(23 downto 0);
signal pc_rgb_delay :pc_rgb_array;
signal legacy_r,legacy_g,legacy_b :std_logic_vector(3 downto 0);
signal pc_single_pixel :std_logic;


begin
	-- The resettable divide-by-three pixel clock has three possible phases.
	-- Direct CPU-to-pixel paths needed enough route delay for one phase's hold
	-- check that another phase missed setup. This parent-clock stage splits
	-- the transfer; both crossings keep their normal setup/hold constraints.
	-- No scan counters, pixel data or palette values pass through this stage.
	-- These are unconditional pipeline registers, not state. They refresh on
	-- every parent-clock edge, including while reset is asserted. The pixel
	-- reset remains asserted for two pixel edges after parent reset releases,
	-- so consumers cannot run before the settings stage has been filled.
	process(clk) begin
		if rising_edge(clk) then
			tbaseaddr_video <= TBASEADDR;
			tpitch_video <= TPITCH;
			hmode_video <= HMODE;
            atrsel_video <= ATRSEL;
            pc_video<=PC_FAST & PC_PAGE & PC_SINGLE & PC_MODE & PC_B1HI & PC_B0HI;
			vlines_video <= VLINES;
			curaddr_video <= CURADDR;
			cure_video <= CURE;
			curupper_video <= CURUPPER;
			curlower_video <= CURLOWER;
			cblink_video <= CBLINK;
			blinkrate_video <= BLINKRATE;
			gbaseaddr0_video <= GBASEADDR0;
			gbaseaddr1_video <= GBASEADDR1;
			glinenum0_video <= GLINENUM0;
			glinenum1_video <= GLINENUM1;
			gbaseaddr2_video <= GBASEADDR2;
			gbaseaddr3_video <= GBASEADDR3;
			glinenum2_video <= GLINENUM2;
			glinenum3_video <= GLINENUM3;
			gpitch_video <= GPITCH;
			dotpline_video <= DOTPLINE;
			graphen_video <= GRAPHEN;
			txten_video <= TXTEN;
			lowbl_video <= LOWBL;
		end if;
	end process;

    -- Derived pixel rising edges follow parent rising edges. Stage the
    -- held settings on the opposite edge so their next transition cannot
    -- overtake the pixel clock. Both half-cycle paths remain normally timed.
    process(clk) begin
        if falling_edge(clk) then
            tbaseaddr_pixel_source <= tbaseaddr_video;
            tpitch_pixel_source <= tpitch_video;
            hmode_pixel_source <= hmode_video;
            atrsel_pixel_source <= atrsel_video;
            pc_pixel_source<=pc_video;
            vlines_pixel_source <= vlines_video;
            curaddr_pixel_source <= curaddr_video;
            cure_pixel_source <= cure_video;
            curupper_pixel_source <= curupper_video;
            curlower_pixel_source <= curlower_video;
            cblink_pixel_source <= cblink_video;
            blinkrate_pixel_source <= blinkrate_video;
            gbaseaddr0_pixel_source <= gbaseaddr0_video;
            gbaseaddr1_pixel_source <= gbaseaddr1_video;
            glinenum0_pixel_source <= glinenum0_video;
            glinenum1_pixel_source <= glinenum1_video;
            gbaseaddr2_pixel_source <= gbaseaddr2_video;
            gbaseaddr3_pixel_source <= gbaseaddr3_video;
            glinenum2_pixel_source <= glinenum2_video;
            glinenum3_pixel_source <= glinenum3_video;
            gpitch_pixel_source <= gpitch_video;
            dotpline_pixel_source <= dotpline_video;
            graphen_pixel_source <= graphen_video;
            lowbl_pixel_source <= lowbl_video;
        end if;
    end process;

    packed_raster:entity work.pegc_raster port map(
        clk=>clk3,rstn=>pixel_rstn,mode256=>pc_pixel_source(2),
        single_page=>pc_pixel_source(3),display_page=>pc_pixel_source(4),fast_clock=>pc_pixel_source(5),
        graph_enable=>graphen_pixel_source,base0=>pc_pixel_source(0) & gbaseaddr0_pixel_source,
        base1=>pc_pixel_source(1) & gbaseaddr1_pixel_source,
        length0=>glinenum0_pixel_source,length1=>glinenum1_pixel_source,
        pitch=>gpitch_pixel_source,repeat_lines=>dotpline_pixel_source,
        hunit=>HUCOUNT,dot=>UCOUNT,row=>VCOUNT,
        line_start=>PC_LINE_START,line_enable=>PC_LINE_ENABLE,active=>PC_ACTIVE,
        line_address=>PC_LINE_ADDRESS,pixel_x=>PC_X,mode_pixel=>pc_mode_pixel);
    PC_RSTN<=pixel_rstn;
    PC_PAGE_WRAP<=not pc_single_pixel;
    process(clk3,pixel_rstn) begin
        if pixel_rstn='0' then
            pc_single_pixel<='0';pc_mode_delay<=(others=>'0');pc_valid_delay<=(others=>'0');
            pc_rgb_delay<=(others=>(others=>'0'));
        elsif rising_edge(clk3) then
            pc_single_pixel<=pc_pixel_source(3);
            pc_mode_delay<=pc_mode_delay(7 downto 0) & pc_mode_pixel;
            pc_valid_delay<=pc_valid_delay(5 downto 0) & PC_VALID;
            pc_rgb_delay(0)<=PC_RGB;
            for i in 1 to 5 loop pc_rgb_delay(i)<=pc_rgb_delay(i-1);end loop;
        end if;
    end process;
    -- Existing text/sync are nine clocks after the raw pixel coordinate.
    -- Line RAM+byte selection+palette take three clocks: delay RGB six more,
    -- and valid seven after its two-clock line-reader pipeline.
    ROUT<=legacy_r;GOUT<=legacy_g;BOUT<=legacy_b;
    ROUT8<=legacy_r & legacy_r when pc_mode_delay(8)='0' or EMUMODE='1' or (T_BIT='1' and txten_video='1') else
           pc_rgb_delay(5)(23 downto 16) when VISIBLE='1' and pc_valid_delay(6)='1' else x"00";
    GOUT8<=legacy_g & legacy_g when pc_mode_delay(8)='0' or EMUMODE='1' or (T_BIT='1' and txten_video='1') else
           pc_rgb_delay(5)(15 downto 8) when VISIBLE='1' and pc_valid_delay(6)='1' else x"00";
    BOUT8<=legacy_b & legacy_b when pc_mode_delay(8)='0' or EMUMODE='1' or (T_BIT='1' and txten_video='1') else
           pc_rgb_delay(5)(7 downto 0) when VISIBLE='1' and pc_valid_delay(6)='1' else x"00";

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
	VSY		=>VSY,
    EXTERNAL_PIXEL_RESET=>true
	) port map(VCOUNT,HUCOUNT,UCOUNT,HCOMP,VCOMP,clk2,clk3,clk,rstn,pixel_rstn);
	
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
		
		CURADDR	=>curaddr_pixel_source,
		CURE	=>cure_pixel_source,
		CURUPPER=>curupper_pixel_source,
		CURLOWER=>curlower_pixel_source,
		CBLINK	=>cblink_pixel_source,
		BLINKRATE=>blinkrate_pixel_source,
		
		BASEADDR=>tbaseaddr_pixel_source,
		HMODE	=>hmode_pixel_source,
        ATRSEL=>atrsel_pixel_source,
		VLINES	=>vlines_pixel_source,
		PITCH	=>tpitch_pixel_source,
		
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

		GRAPHEN	=>graphen_pixel_source,
		DOTPLINE=>dotpline_pixel_source,
		BLANK	=>lowbl_pixel_source,
		
		UCOUNT	=>UCOUNT,
		HUCOUNT	=>HUCOUNT,
		VCOUNT	=>VCOUNT,
		HCOMP	=>HCOMP,
		VCOMP	=>VCOMP,

		BASEADDR0=>gbaseaddr0_pixel_source,
		BASEADDR1=>gbaseaddr1_pixel_source,
		LINENUM0=>glinenum0_pixel_source,
		LINENUM1=>glinenum1_pixel_source,
		BASEADDR2=>gbaseaddr2_pixel_source,
		BASEADDR3=>gbaseaddr3_pixel_source,
		LINENUM2=>glinenum2_pixel_source,
		LINENUM3=>glinenum3_pixel_source,
		PITCH	=>gpitch_pixel_source,
		
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

	GRPHB<=	x"0" when graphen_video='0' else
				x"0" when G_DOTE='0' else
				GPALB;

	GRPHR<=	x"0" when graphen_video='0' else
				x"0" when G_DOTE='0' else
				GPALR;

	GRPHG<=	x"0" when graphen_video='0' else
				x"0" when G_DOTE='0' else
				GPALG;

	GPALNO<=G_DOT;

	legacy_b<="0000" when VISIBLE='0' else 
			(others=>EF_COLOR(0)) when EMUMODE='1' and ET_BIT='1' else
			(others=>EB_COLOR(0)) when EMUMODE='1' and ET_BIT='0' else
			"1111" when TCOLOR(0)='1' and T_BIT='1' and txten_video='1' else
			"0000" when T_BIT='1' and txten_video='1' else
			GRPHB;
	legacy_r<="0000" when VISIBLE='0' else 
			(others=>EF_COLOR(2)) when EMUMODE='1' and ET_BIT='1' else
			(others=>EB_COLOR(2)) when EMUMODE='1' and ET_BIT='0' else
			"1111" when TCOLOR(1)='1' and T_BIT='1' and txten_video='1' else
			"0000" when T_BIT='1' and txten_video='1' else
			GRPHR;
	legacy_g<="0000" when VISIBLE='0' else 
			(others=>EF_COLOR(1)) when EMUMODE='1' and ET_BIT='1' else
			(others=>EB_COLOR(1)) when EMUMODE='1' and ET_BIT='0' else
			"1111" when TCOLOR(2)='1' and T_BIT='1' and txten_video='1' else
			"0000" when T_BIT='1' and txten_video='1' else
			GRPHG;

	gclk<=clk3;

end MAIN;
