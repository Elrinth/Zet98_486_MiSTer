library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.VIDEO_TIMING_pkg.all;

entity GRAPHSCR98 is
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
end GRAPHSCR98;

architecture MAIN of GRAPHSCR98 is
component graphbuf816
	PORT
	(
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		rdaddress		: IN STD_LOGIC_VECTOR (6 DOWNTO 0);
		wraddress		: IN STD_LOGIC_VECTOR (5 DOWNTO 0);
		wren		: IN STD_LOGIC  := '0';
		q		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END component;

component delayer is
generic(
	counts	:integer	:=5
);
port(
	a		:in std_logic;
	q		:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

signal	WDAT0	:std_logic_vector(15 downto 0);
signal	WDAT1	:std_logic_vector(15 downto 0);
signal	WDAT2	:std_logic_vector(15 downto 0);
signal	WDAT3	:std_logic_vector(15 downto 0);
signal	RDAT0	:std_logic_vector(7 downto 0);
signal	RDAT1	:std_logic_vector(7 downto 0);
signal	RDAT2	:std_logic_vector(7 downto 0);
signal	RDAT3	:std_logic_vector(7 downto 0);
signal	BUFWE	:std_logic;
signal	WADR	:std_logic_vector(5 downto 0);
signal	RADR	:std_logic_vector(6 downto 0);
type BUFST_T is (
	BS_IDLE,
	BS_READ,
	BS_WRITE
);
signal	BUFSTATE	:BUFST_T;
signal	BUFCNT	:integer range 0 to HUVIS-1;
signal	LOWRESb	:std_logic;
signal	LINEEN	:std_logic;
signal	LINECOUNT	:std_logic_vector(4 downto 0);
signal	NXTDOT0	:std_logic_vector(7 downto 0);
signal	NXTDOT1	:std_logic_vector(7 downto 0);
signal	NXTDOT2	:std_logic_vector(7 downto 0);
signal	NXTDOT3	:std_logic_vector(7 downto 0);
signal	CURDOT0	:std_logic_vector(7 downto 0);
signal	CURDOT1	:std_logic_vector(7 downto 0);
signal	CURDOT2	:std_logic_vector(7 downto 0);
signal	CURDOT3	:std_logic_vector(7 downto 0);
signal	DHCOMP	:std_logic;
signal	DVCOMP	:std_logic;
signal	GRAMADRb:std_logic_vector(13 downto 0);
signal	MONOFL0	:std_logic_vector(7 downto 0);
signal	MONOFL1	:std_logic_vector(7 downto 0);
signal	MONOFL2	:std_logic_vector(7 downto 0);
signal	C0ADDR	:std_logic_vector(13 downto 0);
signal	iLINENUM0	:integer range 0 to 1023;
signal	lvcount	:std_logic_vector(9 downto 0);
-- Related system/pixel clocks remain fully timed. Register GDC settings
-- before address/count arithmetic, without asynchronous-path exceptions.
signal base0_pixel, base1_pixel : std_logic_vector(13 downto 0);
signal length0_pixel : std_logic_vector(9 downto 0);
signal pitch_pixel : std_logic_vector(7 downto 0);
signal repeat_pixel : std_logic_vector(4 downto 0);

begin
	buf0	:graphbuf816 port map(clk,WDAT0,RADR,WADR,BUFWE,RDAT0);
	buf1	:graphbuf816 port map(clk,WDAT1,RADR,WADR,BUFWE,RDAT1);
	buf2	:graphbuf816 port map(clk,WDAT2,RADR,WADR,BUFWE,RDAT2);
	buf3	:graphbuf816 port map(clk,WDAT3,RADR,WADR,BUFWE,RDAT3);
	
	lvcount<=conv_std_logic_vector(vcount,10);
	
	GRAMADR<=GRAMADRb;
	
	iLINENUM0<=conv_integer(length0_pixel);
    process(clk,rstn) begin
        if rstn='0' then
            base0_pixel<=(others=>'0');base1_pixel<=(others=>'0');
            length0_pixel<=(others=>'0');pitch_pixel<=(others=>'0');repeat_pixel<=(others=>'0');
        elsif rising_edge(clk) then
            base0_pixel<=BASEADDR0;base1_pixel<=BASEADDR1;
            length0_pixel<=LINENUM0;pitch_pixel<=PITCH;repeat_pixel<=DOTPLINE;
        end if;
    end process;
	
	process(clk,rstn)
	variable LINENUM	:integer range 0 to 1023;
    variable first_partition : boolean;
	begin
		if(rstn='0')then
			BUFSTATE<=BS_IDLE;
			WADR<=(others=>'0');
			GRAMADRb<=(others=>'0');
			C0ADDR<=(others=>'0');
			GRAMRD<='0';
			BUFWE<='0';
			BUFCNT<=0;
			LINEEN<='1';
			LINENUM:=1;
            first_partition:=true;
			LINECOUNT<="00000";
		elsif(clk' event and clk='1')then
			BUFWE<='0';
			case BUFSTATE is
			when BS_IDLE =>
				if(HUCOUNT=0 and UCOUNT=0 and VCOUNT>=VIV)then
					if(VCOUNT=VIV)then
                        GRAMADRb<=base0_pixel;
                        C0ADDR<=base0_pixel;
                        LINEEN<='1';
                        LINENUM:=1;
                        first_partition:=true;
                        LINECOUNT<=repeat_pixel;
                        BUFSTATE<=BS_READ;
                        GRAMRD<='1';
                    elsif(LINECOUNT="00000")then
                        -- Count logical rows upwards; repeated raster lines
                        -- neither consume a partition row nor request SDRAM.
                        if first_partition and LINENUM=iLINENUM0 then
                            GRAMADRb<=base1_pixel;
                            C0ADDR<=base1_pixel;
                            first_partition:=false;
                        else
                            GRAMADRb<=C0ADDR+pitch_pixel;
                            C0ADDR<=C0ADDR+pitch_pixel;
                        end if;
                        BUFSTATE<=BS_READ;
                        GRAMRD<='1';
                        LINENUM:=(LINENUM+1) mod 1024;
                        LINECOUNT<=repeat_pixel;
                        LINEEN<='1';
					else
						LINECOUNT<=LINECOUNT-1;
						LINEEN<='0';
					end if;
					BUFCNT<=0;
					WADR<=(others=>'0');
				end if;
			when BS_READ =>
				if(GRAMACK='1')then
                    -- The memory result is already stable at ACK. Capture it
                    -- before the existing next-edge line-buffer write, keeping
                    -- RAM input timing entirely in the pixel clock domain.
                    WDAT0<=GRAMDAT0; WDAT1<=GRAMDAT1;
                    WDAT2<=GRAMDAT2; WDAT3<=GRAMDAT3;
					BUFWE<='1';
					BUFSTATE<=BS_WRITE;
					GRAMRD<='0';
				end if;
			when BS_WRITE =>
				GRAMADRb<=GRAMADRb+1;
				WADR<=WADR+1;
				if(BUFCNT<((HUVIS/2)-1))then
					BUFSTATE<=BS_READ;
					GRAMRD<='1';
					BUFCNT<=BUFCNT+1;
				else
					BUFSTATE<=BS_IDLE;
				end if;
			when others =>
				BUFSTATE<=BS_IDLE;
			end case;
		end if;
	end process;

	Hdelay	:delayer generic map(2) port map(HCOMP,DHCOMP,clk,rstn);
	Vdelay	:delayer generic map(4) port map(VCOMP,DVCOMP,clk,rstn);
	
	process (clk,rstn)
	variable VVISCOUNT :integer range 0 to VVIS-1;
	variable VVISCV	:std_logic_vector(8 downto 0);
	variable BNXTDOT	:std_logic_vector(7 downto 0);
	begin
		if(rstn='0')then
			NXTDOT0<=(others=>'0');
			NXTDOT1<=(others=>'0');
			NXTDOT2<=(others=>'0');
			NXTDOT3<=(others=>'0');
			RADR<=(others=>'0');
		elsif(clk' event and clk='1')then

-- Data	section
			if(DHCOMP='1')then
				RADR<=(others=>'0');
			end if;

			if(VCOUNT>=VIV)then
				VVISCOUNT:=VCOUNT-VIV;
			else
				VVISCOUNT:=0;
			end if;
			VVISCV:=conv_std_logic_vector(VVISCOUNT,9);

			if(UCOUNT=4)then
				if(VCOUNT>=VIV and HUCOUNT>=HIV)then
					NXTDOT0<=RDAT0;
					NXTDOT1<=RDAT1;
					NXTDOT2<=RDAT2;
					NXTDOT3<=RDAT3;
					RADR<=RADR+1;
				else
					NXTDOT0<=(others=>'0');
					NXTDOT1<=(others=>'0');
					NXTDOT2<=(others=>'0');
					NXTDOT3<=(others=>'0');
				end if;
			end if;
		end if;
	end process;
	
-- Display driver section
	process(clk,rstn)begin
		if(rstn='0')then
			DOTOUT<="0000";
			DOTE<='0';
			CURDOT0<=(others=>'0');
			CURDOT1<=(others=>'0');
			CURDOT2<=(others=>'0');
			CURDOT3<=(others=>'0');
		elsif(clk' event and clk='1')then
			if(UCOUNT=0)then
				DOTOUT(0)<=NXTDOT0(7);
				DOTOUT(1)<=NXTDOT1(7);
				DOTOUT(2)<=NXTDOT2(7);
				DOTOUT(3)<=NXTDOT3(7);
				DOTE<=(not BLANK) or lvcount(0);
				CURDOT0<=NXTDOT0;
				CURDOT1<=NXTDOT1;
				CURDOT2<=NXTDOT2;
				CURDOT3<=NXTDOT3;
			else
				DOTOUT(0)<=CURDOT0(6);
				DOTOUT(1)<=CURDOT1(6);
				DOTOUT(2)<=CURDOT2(6);
				DOTOUT(3)<=CURDOT3(6);
				CURDOT0<=CURDOT0(6 downto 0) & '0';
				CURDOT1<=CURDOT1(6 downto 0) & '0';
				CURDOT2<=CURDOT2(6 downto 0) & '0';
				CURDOT3<=CURDOT3(6 downto 0) & '0';
			end if;
		end if;
	end process;

end MAIN;
				
