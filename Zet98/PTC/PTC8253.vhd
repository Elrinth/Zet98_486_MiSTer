LIBRARY	IEEE;
	USE	IEEE.STD_LOGIC_1164.ALL;
	USE IEEE.STD_LOGIC_ARITH.ALL;
	USE	IEEE.STD_LOGIC_UNSIGNED.ALL;

entity PTC8253 is
port(
	CS		:in std_logic;
	ADDR	:in std_logic_vector(1 downto 0);
	RD		:in std_logic;
	WR		:in std_logic;
	RDAT	:out std_logic_vector(7 downto 0);
	WDAT	:in std_logic_vector(7 downto 0);
	DOE		:out std_logic;
	
	CNTIN	:in std_logic_vector(2 downto 0);
	TRIG	:in std_logic_vector(2 downto 0);
	CNTOUT	:out std_logic_vector(2 downto 0);
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end PTC8253;

architecture rtl of PTC8253 is
signal	RWMODE0	:std_logic_vector(1 downto 0);
signal	RWMODE1	:std_logic_vector(1 downto 0);
signal	RWMODE2	:std_logic_vector(1 downto 0);
signal	CNTLAT	:std_logic_vector(2 downto 0);
signal	OPMODE0	:std_logic_vector(2 downto 0);
signal	OPMODE1	:std_logic_vector(2 downto 0);
signal	OPMODE2	:std_logic_vector(2 downto 0);
signal	OPBCD	:std_logic_vector(2 downto 0);
signal	CHRD	:std_logic_vector(2 downto 0);
signal	CHWR	:std_logic_vector(2 downto 0);
signal	CH0RDAT	:std_logic_vector(7 downto 0);
signal	CH1RDAT	:std_logic_vector(7 downto 0);
signal	CH2RDAT	:std_logic_vector(7 downto 0);
signal	CHDOE	:std_logic_Vector(2 downto 0);

component PTC1ch
port(
	RD		:in std_logic;
	WR		:in std_logic;
	RDAT	:out std_logic_vector(7 downto 0);
	WDAT	:in std_logic_vector(7 downto 0);
	OE		:out std_logic;
	
	RWMODE	:in std_logic_vector(1 downto 0);
	CNTLAT	:in std_logic;
	OPMODE	:in std_logic_vector(2 downto 0);
	OPBCD	:in std_logic;
	CTLWR	:in std_logic;
	CTLMODE	:in std_logic_vector(2 downto 0);
	
	CNTIN	:in std_logic;
	TRIG	:in std_logic;
	CNTOUT	:out std_logic;
	
	clk		:in std_logic;
	rstn	:in std_logic
);
end component;

signal	CTLWR	:std_logic_vector(2 downto 0);
begin

	-- A control word (not a counter latch) for channel n: the channel sets
	-- OUT's initial state and holds counting until its new count is loaded.
	CTLWR(0)<='1' when CS='1' and WR='1' and ADDR="11" and WDAT(7 downto 6)="00" and WDAT(5 downto 4)/="00" else '0';
	CTLWR(1)<='1' when CS='1' and WR='1' and ADDR="11" and WDAT(7 downto 6)="01" and WDAT(5 downto 4)/="00" else '0';
	CTLWR(2)<='1' when CS='1' and WR='1' and ADDR="11" and WDAT(7 downto 6)="10" and WDAT(5 downto 4)/="00" else '0';

	process(clk,rstn)begin
		if(rstn='0')then
			RWMODE0<=(others=>'0');
			RWMODE1<=(others=>'0');
			RWMODE2<=(others=>'0');
			CNTLAT<=(others=>'0');
			OPMODE0<=(others=>'0');
			OPMODE1<=(others=>'0');
			OPMODE2<=(others=>'0');
			OPBCD<=(others=>'0');
		elsif(clk' event and clk='1')then
			CNTLAT<=(others=>'0');
			if(CS='1' and WR='1' and ADDR="11")then
				case WDAT(7 downto 6) is
				when "00" =>
					if(WDAT(5 downto 4)="00")then
						CNTLAT(0)<='1';		-- latch only: mode and BCD stay
					else
						RWMODE0<=WDAT(5 downto 4);
						OPMODE0<=WDAT(3 downto 1);
						OPBCD(0)<=WDAT(0);
					end if;
				when "01" =>
					if(WDAT(5 downto 4)="00")then
						CNTLAT(1)<='1';		-- latch only: mode and BCD stay
					else
						RWMODE1<=WDAT(5 downto 4);
						OPMODE1<=WDAT(3 downto 1);
						OPBCD(1)<=WDAT(0);
					end if;
				when "10" =>
					if(WDAT(5 downto 4)="00")then
						CNTLAT(2)<='1';		-- latch only: mode and BCD stay
					else
						RWMODE2<=WDAT(5 downto 4);
						OPMODE2<=WDAT(3 downto 1);
						OPBCD(2)<=WDAT(0);
					end if;
				when others =>
				end case;
			end if;
		end if;
	end process;
	
	CHRD<=	"000" when CS='0' or RD='0' else
			"001" when ADDR="00" else
			"010" when ADDR="01" else
			"100" when ADDR="10" else
			"000";

	CHWR<=	"000" when CS='0' or WR='0' else
			"001" when ADDR="00" else
			"010" when ADDR="01" else
			"100" when ADDR="10" else
			"000";
	
	PTC0	:PTC1ch port map(
		RD		=>CHRD(0),
		WR		=>CHWR(0),
		RDAT	=>CH0RDAT,
		WDAT	=>WDAT,
		OE		=>CHDOE(0),
		
		RWMODE	=>RWMODE0,
		CNTLAT	=>CNTLAT(0),
		OPMODE	=>OPMODE0,
		OPBCD	=>OPBCD(0),
		CTLWR	=>CTLWR(0),
		CTLMODE	=>WDAT(3 downto 1),
		
		CNTIN	=>CNTIN(0),
		TRIG	=>TRIG(0),
		CNTOUT	=>CNTOUT(0),
		
		clk		=>clk,
		rstn	=>rstn
	);

	PTC1	:PTC1ch port map(
		RD		=>CHRD(1),
		WR		=>CHWR(1),
		RDAT	=>CH1RDAT,
		WDAT	=>WDAT,
		OE		=>CHDOE(1),
		
		RWMODE	=>RWMODE1,
		CNTLAT	=>CNTLAT(1),
		OPMODE	=>OPMODE1,
		OPBCD	=>OPBCD(1),
		CTLWR	=>CTLWR(1),
		CTLMODE	=>WDAT(3 downto 1),
		
		CNTIN	=>CNTIN(1),
		TRIG	=>TRIG(1),
		CNTOUT	=>CNTOUT(1),
		
		clk		=>clk,
		rstn	=>rstn
	);
	
	PTC2	:PTC1ch port map(
		RD		=>CHRD(2),
		WR		=>CHWR(2),
		RDAT	=>CH2RDAT,
		WDAT	=>WDAT,
		OE		=>CHDOE(2),
		
		RWMODE	=>RWMODE2,
		CNTLAT	=>CNTLAT(2),
		OPMODE	=>OPMODE2,
		OPBCD	=>OPBCD(2),
		CTLWR	=>CTLWR(2),
		CTLMODE	=>WDAT(3 downto 1),
		
		CNTIN	=>CNTIN(2),
		TRIG	=>TRIG(2),
		CNTOUT	=>CNTOUT(2),
		
		clk		=>clk,
		rstn	=>rstn
	);
	
	RDAT<=	CH0RDAT	when CHDOE(0)='1' else
			CH1RDAT	when CHDOE(1)='1' else
			CH2RDAT	when CHDOE(2)='1' else
			(others=>'0');
	DOE<=	'1' when CS='1' and RD='1' else '0';

end rtl;
