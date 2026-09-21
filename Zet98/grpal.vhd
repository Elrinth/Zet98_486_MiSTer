LIBRARY	ieee;
USE ieee.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity grpal is
generic (VIDEO_STAGED : boolean := false);
port(
	CS			:in std_logic;
	ADDR		:in std_logic_vector(1 downto 0);
	WR			:in std_logic;
	RD			:in std_logic;
	WRDAT		:in std_logic_vector(7 downto 0);
	RDDAT		:out std_logic_vector(7 downto 0);
	DOE			:out std_logic;
	
	COLORMODE	:in std_logic;
	NUMIN		:in std_logic_vector(3 downto 0);
	vidR		:out std_logic_vector(3 downto 0);
	vidG		:out std_logic_vector(3 downto 0);
	vidB		:out std_logic_vector(3 downto 0);
	
	clk			:in std_logic;
	rstn		:in std_logic;
    video_clk : in std_logic := '0'
);
end grpal;

architecture rtl of grpal is
subtype PAL_LAT_TYPE is std_logic_vector(11 downto 0); 
type PAL_LAT_ARRAY is array (natural range <>) of PAL_LAT_TYPE; 
signal	PALREG	:PAL_LAT_ARRAY(0 to 15);

subtype C8_LAT_TYPE is std_logic_vector(2 downto 0); 
type C8_LAT_ARRAY is array (natural range <>) of C8_LAT_TYPE; 
signal	C8REG	:C8_LAT_ARRAY(0 to 7);
signal PAL_VIDEO : PAL_LAT_ARRAY(0 to 15);
signal C8_VIDEO : C8_LAT_ARRAY(0 to 7);
signal COLOR_VIDEO : std_logic;

signal	iNUM	:integer range 0 to 15;
signal	iNUM8	:integer range 0 to 7;
signal	iSEL	:integer range 0 to 15;
signal	SEL		:std_logic_vector(3 downto 0);
begin
    -- Stage settings, not pixels: palette lookup and the raster keep their
    -- existing latency. CPU readback always uses the original register bank.
    staged_palette : if VIDEO_STAGED generate
        -- Hold a complete palette until the video domain has copied it.
        -- CPU writes continue normally; writes during a transfer mark the
        -- next snapshot dirty. No palette mux is added to the pixel path.
        signal palette_hold, palette_transfer : std_logic_vector(216 downto 0);
        signal palette_request, palette_ack : std_logic;
        signal request_sync, ack_sync : std_logic_vector(1 downto 0);
        signal dirty, last_color : std_logic;
        signal palette_video_rstn : std_logic;
        attribute preserve : boolean;
        attribute preserve of palette_hold, request_sync, ack_sync : signal is true;
        attribute altera_attribute : string;
        attribute altera_attribute of request_sync, ack_sync : signal is
            "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
    begin
        palette_reset : entity work.reset_release
            port map(video_clk, rstn, palette_video_rstn);
        palette_transfer <= palette_hold;
        process(clk,rstn) begin
            if rstn='0' then
                palette_hold <= (others=>'0');
                palette_request <= '0'; ack_sync <= "00";
                dirty <= '1'; last_color <= '0';
            elsif rising_edge(clk) then
                ack_sync <= ack_sync(0) & palette_ack;
                last_color <= COLORMODE;
                if palette_request=ack_sync(1) and dirty='1' then
                    for i in 0 to 15 loop
                        palette_hold(12*i+11 downto 12*i) <= PALREG(i);
                    end loop;
                    for i in 0 to 7 loop
                        palette_hold(192+3*i+2 downto 192+3*i) <= C8REG(i);
                    end loop;
                    palette_hold(216) <= COLORMODE;
                    palette_request <= not palette_request;
                    dirty <= '0';
                end if;
                -- The snapshot above sees the preceding register bank. A
                -- simultaneous write must therefore request another copy.
                if (CS='1' and WR='1') or COLORMODE/=last_color then
                    dirty <= '1';
                end if;
            end if;
        end process;
        process(video_clk,palette_video_rstn) begin
            if palette_video_rstn='0' then
                request_sync <= "00"; palette_ack <= '0';
                PAL_VIDEO <= (others=>x"000");
                C8_VIDEO <= ("000","010","001","011","100","110","101","111");
                COLOR_VIDEO <= '0';
            elsif rising_edge(video_clk) then
                request_sync <= request_sync(0) & palette_request;
                if request_sync(1)/=palette_ack then
                    for i in 0 to 15 loop
                        PAL_VIDEO(i) <= palette_transfer(12*i+11 downto 12*i);
                    end loop;
                    for i in 0 to 7 loop
                        C8_VIDEO(i) <= palette_transfer(192+3*i+2 downto 192+3*i);
                    end loop;
                    COLOR_VIDEO <= palette_transfer(216);
                    palette_ack <= request_sync(1);
                end if;
            end if;
        end process;
    end generate;
    legacy_palette : if not VIDEO_STAGED generate
        PAL_VIDEO <= PALREG;
        C8_VIDEO <= C8REG;
        COLOR_VIDEO <= COLORMODE;
    end generate;

	iNUM<=conv_integer(NUMIN);
	iNUM8<=conv_integer(NUMIN(2 downto 0));
	
	vidR<=	(others=>C8_VIDEO(iNUM8)(1)) when COLOR_VIDEO='0' else
			PAL_VIDEO(iNUM)(7 downto 4);

	vidG<=	(others=>C8_VIDEO(iNUM8)(2)) when COLOR_VIDEO='0' else
			PAL_VIDEO(iNUM)(11 downto 8);

	vidB<=	(others=>C8_VIDEO(iNUM8)(0)) when COLOR_VIDEO='0' else
			PAL_VIDEO(iNUM)(3 downto 0);

	process(clk,rstn)begin
		if(rstn='0')then
			PALREG<=(others=>x"000");
			C8REG(0)<="000";
			C8REG(1)<="010";
			C8REG(2)<="001";
			C8REG(3)<="011";
			C8REG(4)<="100";
			C8REG(5)<="110";
			C8REG(6)<="101";
			C8REG(7)<="111";
			SEL<=(others=>'0');
		elsif(clk' event and clk='1')then
			if(CS='1' and WR='1')then
				if(COLORMODE='0')then
					case ADDR is
					when "00" =>
						C8REG(7)<=WRDAT(2 downto 0);
						C8REG(3)<=WRDAT(6 downto 4);
					when "01" =>
						C8REG(5)<=WRDAT(2 downto 0);
						C8REG(1)<=WRDAT(6 downto 4);
					when "10" =>
						C8REG(6)<=WRDAT(2 downto 0);
						C8REG(2)<=WRDAT(6 downto 4);
					when "11" =>
						C8REG(4)<=WRDAT(2 downto 0);
						C8REG(0)<=WRDAT(6 downto 4);
					when others =>
					end case;
				else
					case ADDR is
					when "00" =>
						SEL<=WRDAT(3 downto 0);
					when "01" =>
						PALREG(iSEL)(11 downto 8)<=WRDAT(3 downto 0);
					when "10" =>
						PALREG(iSEL)(7 downto 4)<=WRDAT(3 downto 0);
					when "11" =>
						PALREG(iSEL)(3 downto 0)<=WRDAT(3 downto 0);
					when others =>
					end case;
				end if;
			end if;
		end if;
	end process;
	
	iSEL<=conv_integer(SEL);
	DOE<='1' when CS='1' and RD='1' else '0';
	
	RDDAT<=	'0' & C8REG(3) & '0' & C8REG(7) when ADDR="00" and COLORMODE='0' else
			'0' & C8REG(2) & '0' & C8REG(6) when ADDR="01" and COLORMODE='0' else
			'0' & C8REG(1) & '0' & C8REG(5) when ADDR="10" and COLORMODE='0' else
			'0' & C8REG(0) & '0' & C8REG(4) when ADDR="11" and COLORMODE='0' else
			x"0" & SEL when ADDR="00" and COLORMODE='1' else
			x"0" & PALREG(iSEL)(11 downto 8) when ADDR="01" and COLORMODE='1' else
			x"0" & PALREG(iSEL)( 7 downto 4) when ADDR="10" and COLORMODE='1' else
			x"0" & PALREG(iSEL)( 3 downto 0) when ADDR="11" and COLORMODE='1' else
			(others=>'0');

end rtl;
