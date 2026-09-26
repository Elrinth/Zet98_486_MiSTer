LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity grcg is
generic(SPLIT_RMW : boolean := false);
port(
	iocs	:in std_logic;
	ioaddr	:in std_logic;
	iowr	:in std_logic;
	iowdat	:in std_logic_vector(7 downto 0);
	
	pmemcs	:in std_logic;
	ppsel	:in std_logic_vector(1 downto 0);
	prd		:in std_logic;
	pwr		:in std_logic;
	prddat	:out std_logic_vector(15 downto 0);
	pwrdat	:in std_logic_vector(15 downto 0);
	poe		:out std_logic;
	
	memrd1	:out std_logic;
	memrd4	:out std_logic;
	memwr1	:out std_logic;
	memwr4	:out std_logic;
	memrmw1	:out std_logic;
	memrmw4	:out std_logic;
	memrdat0:in std_logic_vector(15 downto 0);
	memrdat1:in std_logic_vector(15 downto 0);
	memrdat2:in std_logic_vector(15 downto 0);
	memrdat3:in std_logic_vector(15 downto 0);
	memwdat0:out std_logic_vector(15 downto 0);
	memwdat1:out std_logic_vector(15 downto 0);
	memwdat2:out std_logic_vector(15 downto 0);
	memwdat3:out std_logic_vector(15 downto 0);
	memwmask :out std_logic_vector(15 downto 0);
	memwrpsel	:out std_logic_vector(3 downto 0);
	cgenout	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end grcg;

architecture rtl of grcg is
signal	CGEN	:std_logic;
signal	RMWMODE	:std_logic;
signal	PGEN	:std_logic_vector(3 downto 0);
signal	tile0	:std_logic_vector(7 downto 0);
signal	tile1	:std_logic_vector(7 downto 0);
signal	tile2	:std_logic_vector(7 downto 0);
signal	tile3	:std_logic_vector(7 downto 0);
signal	tilenum	:integer range 0 to 3;
signal compare0,compare1,compare2,compare3 :std_logic_vector(15 downto 0);
begin
    -- Split mode sends a static set/preserve pair to the SDRAM controller.
    -- The controller merges its newly read plane data in the memory domain.
    memwmask <= not pwrdat when SPLIT_RMW and CGEN='1' and RMWMODE='1' else x"0000";
	
	process(clk,rstn)
	variable lwr	:std_logic_vector(1 downto 0);
	begin
		if(rstn='0')then
			tile0<=(others=>'0');
			tile1<=(others=>'0');
			tile2<=(others=>'0');
			tile3<=(others=>'0');
			tilenum<=0;
			lwr:="00";
			CGEN<='0';
			RMWMODE<='0';
			PGEN<=(others=>'1');
		elsif(clk' event and clk='1')then
			if(iocs='1' and iowr='1')then
				case ioaddr is
				when '0' =>
					CGEN<=iowdat(7);
					RMWMODE<=iowdat(6);
					PGEN<=not iowdat(3 downto 0);
				when '1' =>
					case tilenum is
					when 0 =>
						tile0<=iowdat;
					when 1 =>
						tile1<=iowdat;
					when 2 =>
						tile2<=iowdat;
					when 3 =>
						tile3<=iowdat;
					when others =>
					end case;
				when others =>
				end case;
			end if;
			lwr(1):=lwr(0);
			lwr(0):=iocs and iowr and ioaddr;
			-- A mode write starts a new B,R,G,E tile sequence, including
			-- when software abandoned an earlier partial sequence.
			if(iocs='1' and iowr='1' and ioaddr='0')then
				tilenum<=0; -- GRCG_MODE_RESTART
			elsif(lwr="10")then
				if(tilenum<3)then
					tilenum<=tilenum+1;
				else
					tilenum<=0;
				end if;
			end if;
		end if;
	end process;
	
	memwrpsel<=	PGEN 	when CGEN='1' else
				"0001"	when ppsel="00" else
				"0010"	when ppsel="01" else
				"0100"	when ppsel="10" else
				"1000"	when ppsel="11" else
				"0000";
	
	memwr1<=	'0'	when pmemcs='0' else
				pwr	when CGEN='0' else
				'0';
	
	memwr4<=	'0'	when pmemcs='0' else
				pwr when CGEN='1' and RMWMODE='0' else
				'0';
	
	memrmw1<=	'0';
	
	memrmw4<=	'0'	when pmemcs='0' else
				pwr when CGEN='1' and RMWMODE='1' else
				'0';
	
	memwdat0<=	pwrdat 			when CGEN='0' else
				tile0 & tile0	when RMWMODE='0' else
				((tile0 & tile0) and pwrdat) when SPLIT_RMW else
				((tile0 & tile0) and pwrdat) or (memrdat0 and (not pwrdat));

	memwdat1<=	(others=>'0')	when CGEN='0' else
				tile1 & tile1	when RMWMODE='0' else
				((tile1 & tile1) and pwrdat) when SPLIT_RMW else
				((tile1 & tile1) and pwrdat) or (memrdat1 and (not pwrdat));
	
	memwdat2<=	(others=>'0')	when CGEN='0' else
				tile2 & tile2	when RMWMODE='0' else
				((tile2 & tile2) and pwrdat) when SPLIT_RMW else
				((tile2 & tile2) and pwrdat) or (memrdat2 and (not pwrdat));
	
	memwdat3<=	(others=>'0')	when CGEN='0' else
				tile3 & tile3	when RMWMODE='0' else
				((tile3 & tile3) and pwrdat) when SPLIT_RMW else
				((tile3 & tile3) and pwrdat) or (memrdat3 and (not pwrdat));
	
	memrd1<=	prd when pmemcs='1' and (CGEN='0' or RMWMODE='1') else '0';
				
	memrd4<=	prd when pmemcs='1' and CGEN='1' and RMWMODE='0' else '0';

	-- TDW reads compare every enabled plane at the same pixel address.
	-- A result bit is one only when all participating color bits match.
	-- Disabled planes are neutral; the CPU address plane is irrelevant.
	compare0 <= not (memrdat0 xor (tile0 & tile0)) when PGEN(0)='1' else x"ffff";
	compare1 <= not (memrdat1 xor (tile1 & tile1)) when PGEN(1)='1' else x"ffff";
	compare2 <= not (memrdat2 xor (tile2 & tile2)) when PGEN(2)='1' else x"ffff";
	compare3 <= not (memrdat3 xor (tile3 & tile3)) when PGEN(3)='1' else x"ffff";
	prddat<=memrdat0 when CGEN='0' or RMWMODE='1' else
		compare0 and compare1 and compare2 and compare3;
	
	poe<=	pmemcs and prd;
	cgenout<=CGEN;
	
end rtl;
	
	
	