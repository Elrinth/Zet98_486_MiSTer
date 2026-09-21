LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;

entity DMASW is
port(
	cpustb	:in std_logic;
	
	dmabreq	:in std_logic;
	
	dmaen	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end DMASW;

architecture rtl of DMASW is
signal	dmaenb	:std_logic;

begin
	process(clk,rstn)
	begin
		if(rstn='0')then
			dmaenb<='0';
		elsif(clk' event and clk='1')then
			if(dmabreq='1')then
				-- Cached code and HLT can leave the CPU bus idle indefinitely.
				-- An idle bus is available without waiting for a new falling edge.
				if(cpustb='0')then
					dmaenb<='1';
				end if;
			elsif(dmabreq='0')then
				dmaenb<='0';
			end if;
		end if;
	end process;
	
	dmaen<=dmaenb;
	
end rtl;
