LIBRARY	ieee;
USE ieee.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity grpal is
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
	rstn		:in std_logic
);
end grpal;

architecture rtl of grpal is
subtype PAL_LAT_TYPE is std_logic_vector(11 downto 0); 
type PAL_LAT_ARRAY is array (natural range <>) of PAL_LAT_TYPE; 
signal	PALREG	:PAL_LAT_ARRAY(0 to 15);

subtype C8_LAT_TYPE is std_logic_vector(2 downto 0); 
type C8_LAT_ARRAY is array (natural range <>) of C8_LAT_TYPE; 
signal	C8REG	:C8_LAT_ARRAY(0 to 7);

signal	iNUM	:integer range 0 to 15;
signal	iNUM8	:integer range 0 to 7;
signal	iSEL	:integer range 0 to 15;
signal	SEL		:std_logic_vector(3 downto 0);
begin
	
	iNUM<=conv_integer(NUMIN);
	iNUM8<=conv_integer(NUMIN(2 downto 0));
	
	vidR<=	(others=>C8REG(iNUM8)(1)) when COLORMODE='0' else
			PALREG(iNUM)(7 downto 4);

	vidG<=	(others=>C8REG(iNUM8)(2)) when COLORMODE='0' else
			PALREG(iNUM)(11 downto 8);

	vidB<=	(others=>C8REG(iNUM8)(0)) when COLORMODE='0' else
			PALREG(iNUM)(3 downto 0);

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
