LIBRARY	IEEE;
USE	IEEE.STD_LOGIC_1164.ALL;
USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity ITFSW is
port(
	CS		:in std_logic;
	WR		:in std_logic;
	DIN		:in std_logic_vector(7 downto 0);
	
	ITFEN	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end ITFSW;

architecture rtl of ITFSW is
begin
	process(clk,rstn)begin
		if(rstn='0')then
			ITFEN<='1';
		elsif(clk' event and clk='1')then
			if(CS='1' and WR='1')then
				case DIN is
				when x"10" =>
					ITFEN<='1';
				when x"12" =>
					ITFEN<='0';
				when others =>
				end case;
			end if;
		end if;
	end process;
end rtl;

